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

<<<<<<< HEAD
@interface TeakRavenLocationHelper ()
@property (strong, nonatomic) NSString* file;
@property (strong, nonatomic) NSNumber* line;
@property (strong, nonatomic) NSString* function;
@property (strong, nonatomic) NSMutableArray* breadcrumbs;
@end

=======
>>>>>>> master
@interface TeakRaven ()
@property (strong, nonatomic) NSURL* endpoint;
@property (strong, nonatomic) NSString* appId;
@property (strong, nonatomic) NSString* sentryKey;
@property (strong, nonatomic) NSString* sentrySecret;
@property (strong, nonatomic) NSMutableDictionary* payloadTemplate;
@property (strong, nonatomic) NSURLSessionConfiguration* urlSessionConfig;
<<<<<<< HEAD
@property (strong, nonatomic) NSArray* runLoopModes;

- (void)reportUncaughtException:(nonnull NSException*)exception;
- (void)reportSignal:(nonnull NSString*)name;
- (void)pumpRunLoops;
=======
>>>>>>> master
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

<<<<<<< HEAD
TeakRaven* uncaughtExceptionHandlerRaven;
void TeakUncaughtExceptionHandler(NSException* exception)
{
   [uncaughtExceptionHandlerRaven reportUncaughtException:exception];
   [uncaughtExceptionHandlerRaven pumpRunLoops];
}

void TeakSignalHandler(int signal)
{
   NSDictionary* sigToString = @{
      [NSNumber numberWithInt:SIGABRT] : @"SIGABRT",
      [NSNumber numberWithInt:SIGILL] : @"SIGILL",
      [NSNumber numberWithInt:SIGSEGV] : @"SIGSEGV",
      [NSNumber numberWithInt:SIGFPE] : @"SIGFPE",
      [NSNumber numberWithInt:SIGBUS] : @"SIGBUS",
      [NSNumber numberWithInt:SIGPIPE] : @"SIGPIPE"
   };
   [uncaughtExceptionHandlerRaven reportSignal:[sigToString objectForKey:[NSNumber numberWithInt:signal]]];
   [uncaughtExceptionHandlerRaven pumpRunLoops];
}

@implementation TeakRaven

- (void)pumpRunLoops
{
   // Dim the window
   UIViewController* dimView = [[UIViewController alloc] initWithNibName:nil bundle:nil];
   [[dimView view] setAlpha:0.5f];
   [[dimView view] setOpaque:NO];
   [[dimView view] setBackgroundColor:[UIColor blackColor]];

   UIWindow* mainWindow = [[UIApplication sharedApplication] keyWindow];
   UIViewController* presenter = [[UIViewController alloc] init];
   [[presenter view] setBackgroundColor:[UIColor clearColor]];
   [[presenter view] setOpaque:NO];
   [mainWindow addSubview:[presenter view]];
   [presenter presentViewController:dimView animated:NO completion:^{
   }];

   // Try and spin to allow for event to send
   NSDate* spinStart = [[NSDate alloc] init];
   while([[[NSDate alloc] init] timeIntervalSinceDate:spinStart] < 3) // Spin for max of # seconds
   {
      for(NSString* mode in uncaughtExceptionHandlerRaven.runLoopModes)
      {
         CFRunLoopRunInMode((CFStringRef)mode, 0.001, false);
      }
   }
}

- (void)setAsUncaughtExceptionHandler
{
   CFRunLoopRef runLoop = CFRunLoopGetMain();
   CFArrayRef allModes = CFRunLoopCopyAllModes(runLoop);
   self.runLoopModes = CFBridgingRelease(allModes);

   uncaughtExceptionHandlerRaven = self;
   NSSetUncaughtExceptionHandler(&TeakUncaughtExceptionHandler);
   signal(SIGABRT, TeakSignalHandler);
   signal(SIGILL, TeakSignalHandler);
   signal(SIGSEGV, TeakSignalHandler);
   signal(SIGFPE, TeakSignalHandler);
   signal(SIGBUS, TeakSignalHandler);
   signal(SIGPIPE, TeakSignalHandler);
}

- (void)reportWithHelper:(TeakRavenLocationHelper*)helper
{
   NSMutableArray* stacktrace = [NSMutableArray arrayWithArray:[TeakRaven stacktraceSkippingFrames:2]];
   NSMutableDictionary* lastFrame = [NSMutableDictionary dictionaryWithDictionary:[stacktrace lastObject]];
   [lastFrame setObject:helper.file forKey:@"filename"];
   [lastFrame setObject:helper.line forKey:@"lineno"];
   [lastFrame setObject:helper.function forKey:@"function"];
   [stacktrace replaceObjectAtIndex:stacktrace.count - 1 withObject:lastFrame];

   NSMutableDictionary* additions = [NSMutableDictionary dictionaryWithDictionary:@{
      @"exception" : @[
         @{
            @"value" : helper.exception.reason,
            @"type" : helper.exception.name,
            @"stacktrace" : @{
               @"frames" : stacktrace
            }
         }
      ]
   }];
   if(helper.breadcrumbs != nil) [additions setObject:helper.breadcrumbs forKey:@"breadcrumbs"];

   TeakRavenReport* report = [[TeakRavenReport alloc] initForRaven:self
                                                             level:TeakRavenLevelError
                                                           message:[NSString stringWithFormat:@"%@: %@", helper.exception.name, helper.exception.reason]
                                                         additions:additions];
   [report send];
}

- (void)reportSignal:(nonnull NSString*)name
{
   NSDictionary* additions = @{
      @"stacktrace" : @{
         @"frames" : [TeakRaven stacktraceSkippingFrames:4]
=======
@implementation TeakRaven

- (void)reportSignal:(nonnull NSString*)name;
{
   NSDictionary* additions = @{
      @"stacktrace" : @{
         @"frames" : [TeakRaven stacktraceFrames]
>>>>>>> master
      }
   };

   TeakRavenReport* report = [[TeakRavenReport alloc] initForRaven:self message:name additions:additions];
   [report send];
}

<<<<<<< HEAD
- (void)reportUncaughtException:(nonnull NSException*)exception
{
=======
- (void)reportUncaughtException:(nonnull NSException*)exception;
{
   [self reportException:exception level:TeakRavenLevelFatal];
}

- (void)reportException:(nonnull NSException*)exception level:(nonnull NSString*)level
{
   NSArray* stacktrace = [TeakRaven stacktraceFrames];

>>>>>>> master
   NSDictionary* additions = @{
      @"exception" : @[
         @{
            @"value" : exception.reason,
            @"type" : exception.name,
            @"stacktrace" : @{
<<<<<<< HEAD
               @"frames" : [TeakRaven stacktraceSkippingFrames:3]
=======
               @"frames" : stacktrace
>>>>>>> master
            }
         }
      ]
   };

   TeakRavenReport* report = [[TeakRavenReport alloc] initForRaven:self
<<<<<<< HEAD
                                                             level:TeakRavenLevelFatal
=======
                                                             level:level
>>>>>>> master
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

<<<<<<< HEAD
- (id)initForTeak:(Teak*)teak
=======
- (id)initForApp:(nonnull NSString*)appId
>>>>>>> master
{
   self = [super init];
   if(self)
   {
<<<<<<< HEAD
      self.appId = @"sdk";
      self.payloadTemplate = [NSMutableDictionary dictionaryWithDictionary: @{
         @"logger" : @"teak",
         @"platform" : @"objc",
         @"release" : teak.sdkVersion,
         @"server_name" : [[NSBundle mainBundle] bundleIdentifier],
         @"tags" : @{
            @"app_id" : teak.appId,
            @"app_version" : teak.appVersion
=======
      self.appId = appId;
      self.payloadTemplate = [NSMutableDictionary dictionaryWithDictionary: @{
         @"logger" : @"teak",
         @"platform" : @"objc",
         @"release" : [Teak sharedInstance].sdkVersion,
         @"server_name" : [[NSBundle mainBundle] bundleIdentifier],
         @"tags" : @{
            @"app_id" : [Teak sharedInstance].appId,
            @"app_version" : [Teak sharedInstance].appVersion
>>>>>>> master
         },
         @"sdk" : @{
            @"name" : @"teak",
            @"version" : TeakSentryVersion
         },
         @"device" : @{
<<<<<<< HEAD
            @"name" : teak.deviceModel,
=======
            @"name" : [Teak sharedInstance].deviceModel,
>>>>>>> master
            @"version" : [NSString stringWithFormat:@"%f",[[[UIDevice currentDevice] systemVersion] floatValue]],
            @"build" : @""
         },
         @"user" : [[NSMutableDictionary alloc] initWithDictionary:@{
<<<<<<< HEAD
            @"device_id" : teak.deviceId
         }]
      }];

      NSString* sessionIdentifier = [NSString stringWithFormat:@"raven.%@.background", self.appId];
=======
            @"device_id" : [Teak sharedInstance].deviceId
         }]
      }];

      NSString* sessionIdentifier = [NSString stringWithFormat:@"raven.%@.background", appId];
>>>>>>> master
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

<<<<<<< HEAD
+ (TeakRaven*)ravenForTeak:(nonnull Teak*)teak
{
   return [[TeakRaven alloc] initForTeak:teak];
}

+ (NSDictionary*)backtraceStrToSentryFrame:(const char*)str
{
   static NSString* progname;
   static dispatch_once_t onceToken;
   dispatch_once(&onceToken, ^{
      progname = [NSString stringWithUTF8String:getprogname()];
   });

   NSString* raw = [NSString stringWithUTF8String:str];
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

   return @{
      @"function" : function,
      @"module" : moduleName,
      @"in_app" : [moduleName isEqualToString:progname] ? @YES : @NO,
      @"address" : [NSString stringWithFormat:@"0x%016llx", address],
      @"raw" : raw
   };
}

+ (NSArray*)stacktraceSkippingFrames:(int)skipFrames
{
   void* callstack[128];
   int frames = backtrace(callstack, 128);
   char **strs = backtrace_symbols(callstack, frames);
=======
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
>>>>>>> master

   NSMutableArray* stacktrace = [NSMutableArray arrayWithCapacity:frames];
   for(int i = frames - 1; i >= skipFrames; i--)
   {
<<<<<<< HEAD
      [stacktrace addObject:[TeakRaven backtraceStrToSentryFrame:strs[i]]];
=======
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
>>>>>>> master
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
<<<<<<< HEAD

@implementation TeakRavenLocationHelper

+ (NSMutableArray*)helperStack
{
   static NSMutableArray* helperStack;
   static dispatch_once_t onceToken;
   dispatch_once(&onceToken, ^{
      helperStack = [[NSMutableArray alloc] init];
   });
   return helperStack;
}

+ (TeakRavenLocationHelper*)pushHelperForFile:(const char*)file line:(int)line function:(const char*)function
{
   NSString* nsFile = [NSString stringWithUTF8String:(strrchr(file, '/') ?: file - 1) + 1];
   NSNumber* nsLine = [NSNumber numberWithInt:line];
   NSString* nsFunction = [NSString stringWithUTF8String:function];
   TeakRavenLocationHelper* helper = [[TeakRavenLocationHelper alloc] initForFile:nsFile line:nsLine function:nsFunction];
   [[TeakRavenLocationHelper helperStack] addObject:helper];
   return helper;
}

+ (TeakRavenLocationHelper*)popHelper
{
   TeakRavenLocationHelper* helper = [[TeakRavenLocationHelper helperStack] lastObject];
   [[TeakRavenLocationHelper helperStack] removeLastObject];
   return helper;
}

+ (TeakRavenLocationHelper*)peekHelper
{
   return [[TeakRavenLocationHelper helperStack] lastObject];
}

- (id)initForFile:(NSString*)file line:(NSNumber*)line function:(NSString*)function
{
   self = [super init];
   if(self)
   {
      self.file = file;
      self.line = line;
      self.function = function;
   }
   return self;
}

- (void)addBreadcrumb:(nonnull NSString*)category message:(NSString*)message data:(NSDictionary*)data file:(const char*)file line:(int)line
{
   if(self.breadcrumbs == nil) self.breadcrumbs = [[NSMutableArray alloc] init];

   NSMutableDictionary* fullData = [NSMutableDictionary dictionaryWithDictionary:@{
      @"file" : [NSString stringWithUTF8String:(strrchr(file, '/') ?: file - 1) + 1],
      @"line" : [NSNumber numberWithInt:line]
   }];
   if(data != nil) [fullData addEntriesFromDictionary:data];

   NSMutableDictionary* breadcrumb = [NSMutableDictionary dictionaryWithDictionary:@{
      @"timestamp" : [NSNumber numberWithDouble:[[[NSDate alloc] init] timeIntervalSince1970]],
      @"category" : category,
      @"data" : fullData
   }];

   if(message != nil) [breadcrumb setValue:message forKey:@"message"];

   [self.breadcrumbs addObject:breadcrumb];
}

@end
=======
>>>>>>> master
