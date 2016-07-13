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
#import "TeakAppConfiguration.h"
#import "TeakDeviceConfiguration.h"

#include <execinfo.h>

#define LOG_TAG "Teak:Sentry"

NSString *const SentryProtocolVersion = @"7";
NSString *const TeakSentryVersion = @"1.0.0";
NSString *const TeakSentryClient = @"teak-ios/1.0.0";

NSString* const TeakRavenLevelError = @"error";
NSString* const TeakRavenLevelFatal = @"fatal";

typedef void(*TeakRavenSignalHandler)(int);

extern bool AmIBeingDebugged(void);

@interface TeakRavenLocationHelper ()
@property (strong, nonatomic) NSString* file;
@property (strong, nonatomic) NSNumber* line;
@property (strong, nonatomic) NSString* function;
@property (strong, nonatomic) NSMutableArray* breadcrumbs;
@end

@interface TeakRaven ()
@property (strong, nonatomic) NSURL* endpoint;
@property (strong, nonatomic) NSString* appId;
@property (strong, nonatomic) NSString* sentryKey;
@property (strong, nonatomic) NSString* sentrySecret;
@property (strong, nonatomic) NSMutableDictionary* payloadTemplate;
@property (strong, nonatomic) NSURLSessionConfiguration* urlSessionConfig;

@property (strong, nonatomic) NSArray* runLoopModes;
@property (nonatomic) NSUncaughtExceptionHandler* hException;
@property (nonatomic) TeakRavenSignalHandler hSIGABRT;
@property (nonatomic) TeakRavenSignalHandler hSIGILL;
@property (nonatomic) TeakRavenSignalHandler hSIGSEGV;
@property (nonatomic) TeakRavenSignalHandler hSIGFPE;
@property (nonatomic) TeakRavenSignalHandler hSIGBUS;
@property (nonatomic) TeakRavenSignalHandler hSIGPIPE;

- (void)reportUncaughtException:(nonnull NSException*)exception;
- (void)reportSignal:(nonnull NSString*)name;
- (void)pumpRunLoops;
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

TeakRaven* uncaughtExceptionHandlerRaven;
void TeakUncaughtExceptionHandler(NSException* exception) {
   [uncaughtExceptionHandlerRaven unsetAsUncaughtExceptionHandler];

   if (AmIBeingDebugged()) {
      TeakLog(@"Build running in debugger, not reporting exception: %@", exception);
   } else {
      [uncaughtExceptionHandlerRaven reportUncaughtException:exception];
      [uncaughtExceptionHandlerRaven pumpRunLoops];
   }
}

void TeakSignalHandler(int signal) {
   [uncaughtExceptionHandlerRaven unsetAsUncaughtExceptionHandler];

   NSDictionary* sigToString = @{
      [NSNumber numberWithInt:SIGABRT] : @"SIGABRT",
      [NSNumber numberWithInt:SIGILL] : @"SIGILL",
      [NSNumber numberWithInt:SIGSEGV] : @"SIGSEGV",
      [NSNumber numberWithInt:SIGFPE] : @"SIGFPE",
      [NSNumber numberWithInt:SIGBUS] : @"SIGBUS",
      [NSNumber numberWithInt:SIGPIPE] : @"SIGPIPE"
   };

   if(AmIBeingDebugged()) {
      TeakLog(@"Build running in debugger, not reporting signal: %@", [sigToString objectForKey:[NSNumber numberWithInt:signal]]);
   } else {
      [uncaughtExceptionHandlerRaven reportSignal:[sigToString objectForKey:[NSNumber numberWithInt:signal]]];
      [uncaughtExceptionHandlerRaven pumpRunLoops];
   }
}

@implementation TeakRaven

- (void)pumpRunLoops {
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
   while ([[[NSDate alloc] init] timeIntervalSinceDate:spinStart] < 3) { // Spin for max of # seconds
      for (NSString* mode in uncaughtExceptionHandlerRaven.runLoopModes) {
         CFRunLoopRunInMode((CFStringRef)mode, 0.001, false);
      }
   }
}

- (void)setAsUncaughtExceptionHandler {
   CFRunLoopRef runLoop = CFRunLoopGetMain();
   CFArrayRef allModes = CFRunLoopCopyAllModes(runLoop);
   self.runLoopModes = CFBridgingRelease(allModes);

   if(uncaughtExceptionHandlerRaven != nil) [uncaughtExceptionHandlerRaven unsetAsUncaughtExceptionHandler];

   self.hException = NSGetUncaughtExceptionHandler();
   NSSetUncaughtExceptionHandler(&TeakUncaughtExceptionHandler);

   struct sigaction previousSignalAction;
#define ASSIGN_SIGNAL_HANDLER(_sig) sigaction(_sig, NULL, &previousSignalAction); self.h##_sig = previousSignalAction.sa_sigaction; signal(_sig,TeakSignalHandler);
   ASSIGN_SIGNAL_HANDLER(SIGABRT);
   ASSIGN_SIGNAL_HANDLER(SIGILL);
   ASSIGN_SIGNAL_HANDLER(SIGSEGV);
   ASSIGN_SIGNAL_HANDLER(SIGFPE);
   ASSIGN_SIGNAL_HANDLER(SIGBUS);
   ASSIGN_SIGNAL_HANDLER(SIGPIPE);
#undef ASSIGN_SIGNAL_HANDLER

   uncaughtExceptionHandlerRaven = self;
}

- (void)unsetAsUncaughtExceptionHandler {
   NSSetUncaughtExceptionHandler(self.hException);
#define RESET_SIGNAL_HANDLER(_sig) signal(_sig,self.h##_sig);
   RESET_SIGNAL_HANDLER(SIGABRT);
   RESET_SIGNAL_HANDLER(SIGILL);
   RESET_SIGNAL_HANDLER(SIGSEGV);
   RESET_SIGNAL_HANDLER(SIGFPE);
   RESET_SIGNAL_HANDLER(SIGBUS);
   RESET_SIGNAL_HANDLER(SIGPIPE);
#undef RESET_SIGNAL_HANDLER
}

- (void)reportWithHelper:(TeakRavenLocationHelper*)helper {
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

- (void)reportSignal:(nonnull NSString*)name {
   [self unsetAsUncaughtExceptionHandler];

   NSDictionary* additions = @{
      @"stacktrace" : @{
         @"frames" : [TeakRaven reverseStacktraceSkippingFrames:3]
      }
   };

   TeakRavenReport* report = [[TeakRavenReport alloc] initForRaven:self message:name additions:additions];
   [report send];
}

- (void)reportUncaughtException:(nonnull NSException*)exception {
   [self unsetAsUncaughtExceptionHandler];

   NSDictionary* additions = @{
      @"exception" : @[
         @{
            @"value" : exception.reason,
            @"type" : exception.name,
            @"stacktrace" : @{
               @"frames" : [TeakRaven stacktraceSkippingFrames:3]
            }
         }
      ]
   };

   TeakRavenReport* report = [[TeakRavenReport alloc] initForRaven:self
                                                             level:TeakRavenLevelFatal
                                                           message:[NSString stringWithFormat:@"%@: %@", exception.name, exception.reason]
                                                         additions:additions];
   [report send];
}

- (void)setUserValue:(id)value forKey:(nonnull NSString*)key {
   NSMutableDictionary* user = [self.payloadTemplate valueForKey:@"user"];
   if (value != nil) {
      [user setValue:value forKey:key];
   } else {
      [user removeObjectForKey:key];
   }
}

- (id)initForTeak:(Teak*)teak {
   self = [super init];
   if(self) {
      @try {
         self.appId = @"sdk";
         self.payloadTemplate = [NSMutableDictionary dictionaryWithDictionary: @{
            @"logger" : @"teak",
            @"platform" : @"objc",
            @"release" : teak.sdkVersion,
            @"server_name" : [[NSBundle mainBundle] bundleIdentifier],
            @"tags" : @{
               @"app_id" : teak.appConfiguration.appId,
               @"app_version" : teak.appConfiguration.appVersion
            },
            @"sdk" : @{
               @"name" : @"teak",
               @"version" : TeakSentryVersion
            },
            @"device" : @{
               @"name" : teak.deviceConfiguration.deviceModel,
               @"version" : teak.deviceConfiguration.platformString,
               @"build" : @""
            },
            @"user" : [[NSMutableDictionary alloc] initWithDictionary:@{
               @"device_id" : teak.deviceConfiguration.deviceId
            }]
         }];
      } @catch (NSException* exception) {
         TeakLog(@"Error creating payload template: %@", exception);
         return nil;
      }

      @try {
         NSString* sessionIdentifier = [NSString stringWithFormat:@"raven.%@.background", self.appId];
         if([NSURLSessionConfiguration respondsToSelector:@selector(backgroundSessionConfigurationWithIdentifier:)]) {
            self.urlSessionConfig = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:sessionIdentifier];
         } else {
            self.urlSessionConfig = [NSURLSessionConfiguration backgroundSessionConfiguration:sessionIdentifier];
         }
         self.urlSessionConfig.discretionary = NO;
         self.urlSessionConfig.allowsCellularAccess = YES;
      } @catch (NSException* exception) {
         // TODO: Don't return nil, instead cache the things
         TeakLog(@"Error creating background NSURLSessionConfiguration: %@", exception);
         return nil;
      }
   }
   return self;
}

- (BOOL)setDSN:(NSString*)dsn {
   BOOL ret = NO;
   @try {
      NSURL* dsnUrl = [NSURL URLWithString:dsn];
      NSMutableArray* pathComponents = [[dsnUrl pathComponents] mutableCopy];

      if (![pathComponents count]) {
         TeakLog(@"Missing path elements.");
         return NO;
      }
      [pathComponents removeObjectAtIndex:0]; // Leading slash

      NSString* projectId = [pathComponents lastObject];
      if (!projectId) {
         TeakLog(@"Unable to find project id in path.");
         return NO;
      }
      [pathComponents removeLastObject]; // Project id

      NSString* path = [pathComponents componentsJoinedByString:@"/"];
      if(![path isEqualToString:@""]) {
         path = [path stringByAppendingString:@"/"];
      }

      if (![dsnUrl user]) {
         TeakLog(@"Unable to find Sentry key in DSN.");
         return NO;
      }

      if (![dsnUrl password]) {
         TeakLog(@"Unable to find Sentry secret in DSN.");
         return NO;
      }

      self.sentryKey = [dsnUrl user];
      self.sentrySecret = [dsnUrl password];
      self.endpoint = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@%@/api/%@/store/", [dsnUrl scheme], [dsnUrl host], path, projectId]];

      ret = YES;
   } @catch (NSException* exception) {
      TeakLog(@"Error assigning DSN: %@", exception);
   }

   return ret;
}

+ (TeakRaven*)ravenForTeak:(nonnull Teak*)teak {
   return [[TeakRaven alloc] initForTeak:teak];
}

+ (NSDictionary*)backtraceStrToSentryFrame:(const char*)str {
   static NSString* progname;
   static dispatch_once_t onceToken;
   dispatch_once(&onceToken, ^{
      progname = [NSString stringWithUTF8String:getprogname()];
   });

   NSString* raw = [NSString stringWithUTF8String:str];
   @try {
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
   } @catch (NSException* exception) {
      return @{
         @"function" : raw == nil ? [NSNull null] : raw
      };
   }
}

+ (NSArray*)stacktraceSkippingFrames:(int)skipFrames {
   void* callstack[128];
   int frames = backtrace(callstack, 128);
   char **strs = backtrace_symbols(callstack, frames);

   NSMutableArray* stacktrace = [NSMutableArray arrayWithCapacity:frames - skipFrames];
   for (int i = frames - 1; i >= skipFrames; i--) {
      [stacktrace addObject:[TeakRaven backtraceStrToSentryFrame:strs[i]]];
   }
   free(strs);

   return stacktrace;
}

+ (NSArray*)reverseStacktraceSkippingFrames:(int)skipFrames {
   void* callstack[128];
   int frames = backtrace(callstack, 128);
   char **strs = backtrace_symbols(callstack, frames);

   NSMutableArray* stacktrace = [NSMutableArray arrayWithCapacity:frames - skipFrames];
   for (int i = skipFrames; i < frames; i++) {
      [stacktrace addObject:[TeakRaven backtraceStrToSentryFrame:strs[i]]];
   }
   free(strs);

   return stacktrace;
}


@end

@implementation TeakRavenReport

- (id)initForRaven:(nonnull TeakRaven*)raven message:(nonnull NSString*)message additions:(NSDictionary*)additions {
   return [self initForRaven:raven level:TeakRavenLevelFatal message:message additions:additions];
}

- (id)initForRaven:(nonnull TeakRaven*)raven level:(nonnull NSString*)level message:(nonnull NSString*)message additions:(NSDictionary*)additions {
   self = [super init];
   if(self) {
      @try {
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

         if (additions != nil) [self.payload addEntriesFromDictionary:additions];
      } @catch( NSException* exception) {
         TeakLog(@"Error creating exception report: %@", exception);
         return nil;
      }
   }
   return self;
}


- (void)send {
   if (self.raven.endpoint == nil) return;

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

- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)dataTask didReceiveResponse:(NSURLResponse*)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
   completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)dataTask didReceiveData:(NSData*)data {
   [self.receivedData appendData:data];
}

- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(NSError*)error {
   if (error) {
      // TODO: Handle error
   }
   else {
      NSDictionary* response = (NSDictionary*)[NSJSONSerialization JSONObjectWithData:self.receivedData options:kNilOptions error:&error];
      NSLog(@"Response: %@", response);
   }
}

+ (NSDateFormatter*)dateFormatter {
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

@implementation TeakRavenLocationHelper

+ (NSMutableArray*)helperStack {
   static NSMutableArray* helperStack;
   static dispatch_once_t onceToken;
   dispatch_once(&onceToken, ^{
      helperStack = [[NSMutableArray alloc] init];
   });
   return helperStack;
}

+ (TeakRavenLocationHelper*)pushHelperForFile:(const char*)file line:(int)line function:(const char*)function {
   NSString* nsFile = [NSString stringWithUTF8String:(strrchr(file, '/') ?: file - 1) + 1];
   NSNumber* nsLine = [NSNumber numberWithInt:line];
   NSString* nsFunction = [NSString stringWithUTF8String:function];
   TeakRavenLocationHelper* helper = [[TeakRavenLocationHelper alloc] initForFile:nsFile line:nsLine function:nsFunction];
   [[TeakRavenLocationHelper helperStack] addObject:helper];
   return helper;
}

+ (TeakRavenLocationHelper*)popHelper {
   TeakRavenLocationHelper* helper = [[TeakRavenLocationHelper helperStack] lastObject];
   [[TeakRavenLocationHelper helperStack] removeLastObject];
   return helper;
}

+ (TeakRavenLocationHelper*)peekHelper {
   return [[TeakRavenLocationHelper helperStack] lastObject];
}

- (id)initForFile:(NSString*)file line:(NSNumber*)line function:(NSString*)function {
   self = [super init];
   if(self) {
      self.file = file;
      self.line = line;
      self.function = function;
   }
   return self;
}

- (void)addBreadcrumb:(nonnull NSString*)category message:(NSString*)message data:(NSDictionary*)data file:(const char*)file line:(int)line {
   if (self.breadcrumbs == nil) self.breadcrumbs = [[NSMutableArray alloc] init];

   NSMutableDictionary* fullData = [NSMutableDictionary dictionaryWithDictionary:@{
      @"file" : [NSString stringWithUTF8String:(strrchr(file, '/') ?: file - 1) + 1],
      @"line" : [NSNumber numberWithInt:line]
   }];
   if(data != nil) [fullData addEntriesFromDictionary:data];

   NSMutableDictionary* breadcrumb = [NSMutableDictionary dictionaryWithDictionary:@{
      @"timestamp" : [NSNumber numberWithDouble:[[[NSDate alloc] init] timeIntervalSince1970]],
      @"category" : category == nil ? @"unknown" : category,
      @"data" : fullData
   }];

   if (message != nil) [breadcrumb setValue:message forKey:@"message"];

   [self.breadcrumbs addObject:breadcrumb];
}

@end
