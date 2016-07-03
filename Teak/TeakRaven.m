/* Teak -- Copyright (C) 2016 GoCarrot Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "TeakRaven.h"
#import "Teak+Internal.h"

#include <execinfo.h>

NSString *const SentryProtocolVersion = @"7";
NSString *const TeakSentryVersion = @"1.0.0";
NSString *const TeakSentryClient = @"teak-ios/1.0.0";

NSString* const TeakRavenLevelError = @"error";
NSString* const TeakRavenLevelFatal = @"fatal";

@interface TeakRaven ()
@property (strong, nonatomic) NSURL* endpoint;
@property (strong, nonatomic) NSString* appId;
@property (strong, nonatomic) NSString* sentryKey;
@property (strong, nonatomic) NSString* sentrySecret;
@property (strong, nonatomic) NSMutableDictionary* payloadTemplate;
@property (strong, nonatomic) NSURLSessionConfiguration* urlSessionConfig;
@end

@interface TeakRavenReport : NSObject <NSURLSessionTaskDelegate, NSURLSessionDataDelegate>
@property (strong, nonatomic) NSMutableData* receivedData;
@property (strong, nonatomic) NSURLSession* urlSession;
@property (strong, nonatomic) NSDate* timestamp;
@property (strong, nonatomic) TeakRaven* raven;
@property (strong, nonatomic) NSMutableDictionary* payload;

- (id)initForRaven:(nonnull TeakRaven*)raven message:(nonnull NSString*)message additions:(NSDictionary*)additions;
- (id)initForRaven:(nonnull TeakRaven*)raven level:(nonnull NSString*)level message:(nonnull NSString*)message additions:(NSDictionary*)additions;

- (void)send;

- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)dataTask didReceiveResponse:(NSURLResponse*)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler;
- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)dataTask didReceiveData:(NSData*)data;
- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(NSError*)error;
@end

@implementation TeakRaven

- (void)reportSignal:(nonnull NSString*)name;
{
   NSDictionary* additions = @{
      @"stacktrace" : @{
         @"frames" : [TeakRaven stacktraceFrames]
      }
   };

   TeakRavenReport* report = [[TeakRavenReport alloc] initForRaven:self message:name additions:additions];
   [report send];
}

- (void)reportUncaughtException:(nonnull NSException*)exception;
{
   [self reportException:exception level:TeakRavenLevelFatal];
}

- (void)reportException:(nonnull NSException*)exception level:(nonnull NSString*)level
{
   NSArray* stacktrace = [TeakRaven stacktraceFrames];

   NSDictionary* additions = @{
      @"exception" : @[
         @{
            @"value" : exception.reason,
            @"type" : exception.name,
            @"stacktrace" : @{
               @"frames" : stacktrace
            }
         }
      ]
   };

   TeakRavenReport* report = [[TeakRavenReport alloc] initForRaven:self
                                                             level:level
                                                           message:[NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]
                                                         additions:additions];
   [report send];
}

- (void)setUserValue:(id)value forKey:(nonnull NSString*)key
{
   NSMutableDictionary* user = [self.payloadTemplate valueForKey:@"user"];
   if(value != nil)
   {
      [user setValue:value forKey:key];
   }
   else
   {
      [user removeObjectForKey:key];
   }
}

- (id)initForApp:(nonnull NSString*)appId
{
   self = [super init];
   if(self)
   {
      self.appId = appId;
      self.payloadTemplate = [NSMutableDictionary dictionaryWithDictionary: @{
         @"logger" : @"teak",
         @"platform" : @"objc",
         @"release" : [Teak sharedInstance].sdkVersion,
         @"server_name" : [[NSBundle mainBundle] bundleIdentifier],
         @"tags" : @{
            @"app_id" : [Teak sharedInstance].appId,
            @"app_version" : [Teak sharedInstance].appVersion
         },
         @"sdk" : @{
            @"name" : @"teak",
            @"version" : TeakSentryVersion
         },
         @"device" : @{
            @"name" : [Teak sharedInstance].deviceModel,
            @"version" : [NSString stringWithFormat:@"%f",[[[UIDevice currentDevice] systemVersion] floatValue]],
            @"build" : @""
         },
         @"user" : [[NSMutableDictionary alloc] initWithDictionary:@{
            @"device_id" : [Teak sharedInstance].deviceId
         }]
      }];

      NSString* sessionIdentifier = [NSString stringWithFormat:@"raven.%@.background", appId];
      if([NSURLSessionConfiguration respondsToSelector:@selector(backgroundSessionConfigurationWithIdentifier:)])
      {
         self.urlSessionConfig = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:sessionIdentifier];
      }
      else
      {
         self.urlSessionConfig = [NSURLSessionConfiguration backgroundSessionConfiguration:sessionIdentifier];
      }
      self.urlSessionConfig.allowsCellularAccess = YES;
   }
   return self;
}

- (BOOL)setDSN:(NSString*)dsn
{
   BOOL ret = NO;
   @try
   {
      NSURL* dsnUrl = [NSURL URLWithString:dsn];
      NSMutableArray* pathComponents = [[dsnUrl pathComponents] mutableCopy];

      if(![pathComponents count])
      {
         NSLog(@"[Teak:Sentry] Missing path elements.");
         return NO;
      }
      [pathComponents removeObjectAtIndex:0]; // Leading slash

      NSString* projectId = [pathComponents lastObject];
      if(!projectId)
      {
         NSLog(@"[Teak:Sentry] Unable to find project id in path.");
         return NO;
      }
      [pathComponents removeLastObject]; // Project id

      NSString* path = [pathComponents componentsJoinedByString:@"/"];
      if(![path isEqualToString:@""])
      {
         path = [path stringByAppendingString:@"/"];
      }

      if(![dsnUrl user])
      {
         NSLog(@"[Teak:Sentry] Unable to find Sentry key in DSN.");
         return NO;
      }

      if(![dsnUrl password])
      {
         NSLog(@"[Teak:Sentry] Unable to find Sentry secret in DSN.");
         return NO;
      }

      self.sentryKey = [dsnUrl user];
      self.sentrySecret = [dsnUrl password];
      self.endpoint = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@%@/api/%@/store/", [dsnUrl scheme], [dsnUrl host], path, projectId]];

      ret = YES;
   }
   @catch(NSException* exception)
   {
      NSLog(@"TODO: method name automagic: %@", exception);
   }

   return ret;
}

+ (TeakRaven*)ravenForApp:(nonnull NSString*)appId
{
   return [[TeakRaven alloc] initForApp:appId];
}

+ (NSArray*)stacktraceFrames
{
   int skipFrames = 4;
   void* callstack[128];
   int frames = backtrace(callstack, 128);
   char **strs = backtrace_symbols(callstack, frames);
   NSString* progname = [NSString stringWithUTF8String:getprogname()];

   NSMutableArray* stacktrace = [NSMutableArray arrayWithCapacity:frames];
   for(int i = frames - 1; i >= skipFrames; i--)
   {
      NSString* raw = [NSString stringWithUTF8String:strs[i]];
      NSScanner* scanner = [NSScanner scannerWithString:raw];

      // Frame #
      [scanner scanInt:nil];

      // Module name
      NSString* moduleName;
      [scanner scanUpToString:@" 0x" intoString:&moduleName];
      moduleName = [moduleName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

      // Hex address
      unsigned long long address;
      [scanner scanHexLongLong:&address];

      // Function + offset is remainder of string
      NSString* function;
      [scanner scanUpToString:@"\n" intoString:&function];

      [stacktrace addObject:@{
         @"function" : function,
         @"module" : moduleName,
         @"in_app" : [moduleName isEqualToString:progname] ? @YES : @NO,
         @"address" : [NSString stringWithFormat:@"0x%016llx", address],
         @"raw" : raw
      }];
   }
   free(strs);

   return stacktrace;
}

@end

@implementation TeakRavenReport

- (id)initForRaven:(nonnull TeakRaven*)raven message:(nonnull NSString*)message additions:(NSDictionary*)additions
{
   return [self initForRaven:raven level:TeakRavenLevelFatal message:message additions:additions];
}

- (id)initForRaven:(nonnull TeakRaven*)raven level:(nonnull NSString*)level message:(nonnull NSString*)message additions:(NSDictionary*)additions
{
   self = [super init];
   if(self)
   {
      self.timestamp = [[NSDate alloc] init];
      self.raven = raven;
      self.receivedData = [[NSMutableData alloc] init];
      [self.receivedData setLength:0];
      self.urlSession = [NSURLSession sessionWithConfiguration:self.raven.urlSessionConfig delegate:self delegateQueue:nil];

      self.payload = [NSMutableDictionary dictionaryWithDictionary:self.raven.payloadTemplate];

      CFUUIDRef theUUID = CFUUIDCreate(NULL);
      CFStringRef string = CFUUIDCreateString(NULL, theUUID);
      CFRelease(theUUID);
      NSString *res = [(__bridge NSString *)string stringByReplacingOccurrencesOfString:@"-" withString:@""];
      CFRelease(string);
      [self.payload setObject:res forKey:@"event_id"];

      [self.payload setObject:[[TeakRavenReport dateFormatter] stringFromDate:self.timestamp] forKey:@"timestamp"];
      [self.payload setObject:level forKey:@"level"];

      NSRange stringRange = {0, MIN([message length], 1000)};
      stringRange = [message rangeOfComposedCharacterSequencesForRange:stringRange];
      [self.payload setObject:[message substringWithRange:stringRange] forKey:@"message"];

      if(additions != nil) [self.payload addEntriesFromDictionary:additions];
   }
   return self;
}


- (void)send
{
   NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:self.raven.endpoint];
   NSData* payloadData = [NSJSONSerialization dataWithJSONObject:self.payload options:0 error:nil];

   [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
   [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
   //[request setValue:@"gzip" forHTTPHeaderField:@"Content-Encoding"]; // TODO: gzip?
   [request setValue:TeakSentryClient forHTTPHeaderField:@"User-Agent"];
   [request setValue:[NSString
                      stringWithFormat:@"Sentry sentry_version=%@,sentry_timestamp=%d,sentry_key=%@,sentry_secret=%@,sentry_client=%@",
                      SentryProtocolVersion, [self.timestamp timeIntervalSince1970], self.raven.sentryKey, self.raven.sentrySecret, TeakSentryClient] forHTTPHeaderField:@"X-Sentry-Auth"];
   [request setHTTPMethod:@"POST"];
   [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[payloadData length]] forHTTPHeaderField:@"Content-Length"];
   [request setHTTPBody:payloadData];

   NSURLSessionDataTask *dataTask = [self.urlSession dataTaskWithRequest:request];
   [dataTask resume];
}

- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)dataTask didReceiveResponse:(NSURLResponse*)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
   completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)dataTask didReceiveData:(NSData*)data
{
   [self.receivedData appendData:data];
}

- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(NSError*)error
{
   if(error)
   {
      // TODO: Handle error
   }
   else
   {
      NSDictionary* response = (NSDictionary*)[NSJSONSerialization JSONObjectWithData:self.receivedData options:kNilOptions error:&error];
      NSLog(@"Response: %@", response);
   }
}

+ (NSDateFormatter*)dateFormatter
{
   static NSDateFormatter* dateFormatter;
   static dispatch_once_t onceToken;
   dispatch_once(&onceToken, ^{
      NSTimeZone *timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
      dateFormatter = [[NSDateFormatter alloc] init];
      [dateFormatter setTimeZone:timeZone];
      [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss"];
   });
   return dateFormatter;
}

@end