#import "TeakRaven.h"
#import "RemoteConfigurationEvent.h"
#import "Teak+Internal.h"
#import "TeakAppConfiguration.h"
#import "TeakDeviceConfiguration.h"
#import "UserIdEvent.h"

#include <execinfo.h>
#include <sys/sysctl.h>

#import "TeakHelpers.h"

NSString* const SentryProtocolVersion = @"7";
NSString* const TeakSentryVersion = @"1.1.0";
NSString* const TeakSentryClient = @"teak-ios/1.1.0";

NSString* const TeakRavenLevelError = @"error";
NSString* const TeakRavenLevelFatal = @"fatal";

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
@property (nonatomic) BOOL isSdkRaven;

@property (strong, nonatomic) NSArray* runLoopModes;
@property (nonatomic) NSUncaughtExceptionHandler* hException;
@property (nonatomic) void* hSIGABRT;
@property (nonatomic) void* hSIGILL;
@property (nonatomic) void* hSIGSEGV;
@property (nonatomic) void* hSIGFPE;
@property (nonatomic) void* hSIGBUS;
@property (nonatomic) void* hSIGPIPE;

- (void)reportUncaughtException:(nonnull NSException*)exception;
- (void)reportSignal:(nonnull NSString*)name;
- (void)pumpRunLoops;
@end

@interface TeakRavenReport : NSObject
@property (strong, nonatomic) NSDate* timestamp;
@property (strong, nonatomic) TeakRaven* raven;
@property (strong, nonatomic) NSMutableDictionary* payload;

- (id)initForRaven:(nonnull TeakRaven*)raven message:(nonnull NSString*)message additions:(NSDictionary*)additions;
- (id)initForRaven:(nonnull TeakRaven*)raven level:(nonnull NSString*)level message:(nonnull NSString*)message additions:(NSDictionary*)additions;

- (void)send;
@end

TeakRaven* uncaughtExceptionHandlerRaven;
void TeakUncaughtExceptionHandler(NSException* exception) {
  [uncaughtExceptionHandlerRaven unsetAsUncaughtExceptionHandler];

  if (AmIBeingDebugged()) {
    NSLog(@"Teak: Build running in debugger, not reporting exception: %@", exception);
  } else {
    [uncaughtExceptionHandlerRaven reportUncaughtException:exception];
    [uncaughtExceptionHandlerRaven pumpRunLoops];
  }
}

void TeakSignalHandler(int signal) {
  [uncaughtExceptionHandlerRaven unsetAsUncaughtExceptionHandler];

  NSDictionary* sigToString = @{
    @SIGABRT : @"SIGABRT",
    @SIGILL : @"SIGILL",
    @SIGSEGV : @"SIGSEGV",
    @SIGFPE : @"SIGFPE",
    @SIGBUS : @"SIGBUS",
    @SIGPIPE : @"SIGPIPE"
  };

  if (AmIBeingDebugged()) {
    NSLog(@"Teak: Build running in debugger, not reporting signal: %@", sigToString[[NSNumber numberWithInt:signal]]);
  } else {
    [uncaughtExceptionHandlerRaven reportSignal:sigToString[[NSNumber numberWithInt:signal]]];
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
  [presenter presentViewController:dimView animated:NO completion:^{}];

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

  if (uncaughtExceptionHandlerRaven != nil) [uncaughtExceptionHandlerRaven unsetAsUncaughtExceptionHandler];

  self.hException = NSGetUncaughtExceptionHandler();
  NSSetUncaughtExceptionHandler(&TeakUncaughtExceptionHandler);

  struct sigaction previousSignalAction;
#define ASSIGN_SIGNAL_HANDLER(_sig)                 \
  sigaction(_sig, NULL, &previousSignalAction);     \
  self.h##_sig = previousSignalAction.sa_sigaction; \
  signal(_sig, TeakSignalHandler);
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
#define RESET_SIGNAL_HANDLER(_sig) signal(_sig, self.h##_sig);
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

  // Future-Pat, you can't get a fully symbolicated stack trace because we're a static framework
  // and even if we weren't, bitcode means we don't get dSYM anyway.
  lastFrame[@"filename"] = helper.file;
  lastFrame[@"lineno"] = helper.line;
  lastFrame[@"function"] = helper.function;
  stacktrace[stacktrace.count - 1] = lastFrame;

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
  if (helper.breadcrumbs != nil) additions[@"breadcrumbs"] = helper.breadcrumbs;

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

- (id)initForAppWithTeak:(Teak*)teak {
  self = [self initForTeak:teak];
  if (self) {
    self.isSdkRaven = NO;
    // self.appId = @"sdk";
  }
  return self;
}

- (id)initForTeak:(Teak*)teak {
  self = [super init];
  if (self) {
    @try {
      size_t size;
      sysctlbyname("hw.machine", NULL, &size, NULL, 0);
      char* tempStr = malloc(size);
      sysctlbyname("hw.machine", tempStr, &size, NULL, 0);
      NSString* hwMachine = [NSString stringWithCString:tempStr encoding:NSUTF8StringEncoding];
      free(tempStr);

      sysctlbyname("hw.model", NULL, &size, NULL, 0);
      tempStr = malloc(size);
      sysctlbyname("hw.model", tempStr, &size, NULL, 0);
      NSString* hwModel = [NSString stringWithCString:tempStr encoding:NSUTF8StringEncoding];
      free(tempStr);

      NSString* family = [[hwMachine componentsSeparatedByCharactersInSet:[NSCharacterSet decimalDigitCharacterSet]] firstObject];

      self.isSdkRaven = YES;
      self.appId = @"sdk";
      self.payloadTemplate = [NSMutableDictionary dictionaryWithDictionary:@{
        @"logger" : @"teak",
        @"platform" : @"objc",
        @"release" : teak.sdkVersion,
        @"tags" : @{},
        @"sdk" : @{
          @"name" : @"teak",
          @"version" : TeakSentryVersion
        },
        @"user" : [[NSMutableDictionary alloc] initWithDictionary:@{
          @"device_id" : teak.configuration.deviceConfiguration.deviceId
        }],
        @"contexts" : @{
          @"os" : @{
            @"name" : @"iOS",
            @"version" : [[UIDevice currentDevice] systemVersion]
          },
          @"app" : @{
            @"app_identifier" : [[NSBundle mainBundle] bundleIdentifier],
            @"teak_app_identifier" : teak.configuration.appConfiguration.appId,
            @"app_version" : teak.configuration.appConfiguration.appVersion,
            @"app_version_name" : teak.configuration.appConfiguration.appVersionName,
            @"build_type" : teak.configuration.appConfiguration.isProduction ? @"production" : @"debug"
          },
          @"device" : @{
            @"family" : family,
            @"model" : hwMachine,
            @"model_id" : hwModel
          }
        }
      }];

      // Listener for User Id
      [TeakEvent addEventHandler:self];
    } @catch (NSException* exception) {
      NSLog(@"Teak: Error creating payload template: %@", exception);
      return nil;
    }
  }
  return self;
}

- (BOOL)setDSN:(NSString*)dsn {
  if (dsn == nil) return NO;

  BOOL ret = NO;
  @try {
    NSURL* dsnUrl = [NSURL URLWithString:dsn];
    NSMutableArray* pathComponents = [[dsnUrl pathComponents] mutableCopy];

    if (![pathComponents count]) {
      NSLog(@"Teak: Missing path elements in Sentry DSN.");
      return NO;
    }
    [pathComponents removeObjectAtIndex:0]; // Leading slash

    NSString* projectId = [pathComponents lastObject];
    if (!projectId) {
      NSLog(@"Teak: Unable to find Sentry project id in path.");
      return NO;
    }
    [pathComponents removeLastObject]; // Project id

    NSString* path = [pathComponents componentsJoinedByString:@"/"];
    if (![path isEqualToString:@""]) {
      path = [path stringByAppendingString:@"/"];
    }

    if (![dsnUrl user]) {
      NSLog(@"Teak: Unable to find Sentry key in DSN.");
      return NO;
    }

    if (![dsnUrl password]) {
      NSLog(@"Teak: Unable to find Sentry secret in DSN.");
      return NO;
    }

    self.sentryKey = [dsnUrl user];
    self.sentrySecret = [dsnUrl password];
    self.endpoint = [NSURL URLWithString:[NSString stringWithFormat:@"%@://%@%@/api/%@/store/", [dsnUrl scheme], [dsnUrl host], path, projectId]];

    ret = YES;
  } @catch (NSException* exception) {
    NSLog(@"Teak: Error assigning Sentry DSN: %@", exception);
  }

  return ret;
}

+ (TeakRaven*)ravenForTeak:(nonnull Teak*)teak {
  return [[TeakRaven alloc] initForTeak:teak];
}

+ (nullable TeakRaven*)ravenForAppWithTeak:(nonnull Teak*)teak {
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
      @"module" : moduleName == nil ? @"nil" : moduleName,
      @"in_app" : [moduleName isEqualToString:progname] ? @YES : @NO,
      @"address" : [NSString stringWithFormat:@"0x%016llx", address],
      @"raw" : raw
    };
  } @catch (NSException* exception) {
    return @{
      @"function" : TeakValueOrNSNull(raw)
    };
  }
}

+ (NSArray*)stacktraceSkippingFrames:(int)skipFrames {
  void* callstack[128];
  int frames = backtrace(callstack, 128);
  char** strs = backtrace_symbols(callstack, frames);

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
  char** strs = backtrace_symbols(callstack, frames);

  NSMutableArray* stacktrace = [NSMutableArray arrayWithCapacity:frames - skipFrames];
  for (int i = skipFrames; i < frames; i++) {
    [stacktrace addObject:[TeakRaven backtraceStrToSentryFrame:strs[i]]];
  }
  free(strs);

  return stacktrace;
}

- (void)dealloc {
  [TeakEvent removeEventHandler:self];
}

- (void)handleEvent:(TeakEvent* _Nonnull)event {
  if (event.type == UserIdentified) {
    NSMutableDictionary* user = [self.payloadTemplate objectForKey:@"user"];
    [user setValue:((UserIdEvent*)event).userId forKey:@"id"];
  } else if (event.type == RemoteConfigurationReady) {
    TeakRemoteConfiguration* remoteConfiguration = ((RemoteConfigurationEvent*)event).remoteConfiguration;
    if (self.isSdkRaven) {
      [self setDSN:remoteConfiguration.sdkSentryDsn];
    } else {
      [self setDSN:remoteConfiguration.appSentryDsn];
    }
  }
}

@end

@implementation TeakRavenReport

- (id)initForRaven:(nonnull TeakRaven*)raven message:(nonnull NSString*)message additions:(NSDictionary*)additions {
  return [self initForRaven:raven level:TeakRavenLevelFatal message:message additions:additions];
}

- (id)initForRaven:(nonnull TeakRaven*)raven level:(nonnull NSString*)level message:(nonnull NSString*)message additions:(NSDictionary*)additions {
  self = [super init];
  if (self) {
    @try {
      self.timestamp = [[NSDate alloc] init];
      self.raven = raven;
      self.payload = [NSMutableDictionary dictionaryWithDictionary:self.raven.payloadTemplate];

      CFUUIDRef theUUID = CFUUIDCreate(NULL);
      CFStringRef string = CFUUIDCreateString(NULL, theUUID);
      CFRelease(theUUID);
      NSString* res = [(__bridge NSString*)string stringByReplacingOccurrencesOfString:@"-" withString:@""];
      CFRelease(string);
      [self.payload setObject:res forKey:@"event_id"];

      [self.payload setObject:[[TeakRavenReport dateFormatter] stringFromDate:self.timestamp] forKey:@"timestamp"];
      [self.payload setObject:level forKey:@"level"];

      NSRange stringRange = {0, MIN([message length], 1000)};
      stringRange = [message rangeOfComposedCharacterSequencesForRange:stringRange];
      [self.payload setObject:[message substringWithRange:stringRange] forKey:@"message"];

      if (additions != nil) [self.payload addEntriesFromDictionary:additions];
    } @catch (NSException* exception) {
      NSLog(@"Teak: Error creating exception report: %@", exception);
      return nil;
    }
  }
  return self;
}

- (void)send {
  if ([Teak sharedInstance].log != nil) {
    TeakLog_e(@"exception", self.payload);
  }

  if (self.raven.endpoint == nil) return;

  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:self.raven.endpoint];
  NSData* payloadData = [NSJSONSerialization dataWithJSONObject:self.payload options:0 error:nil];

  [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
  //[request setValue:@"gzip" forHTTPHeaderField:@"Content-Encoding"]; // TODO: gzip?
  [request setValue:TeakSentryClient forHTTPHeaderField:@"User-Agent"];
  [request setValue:[NSString
                        stringWithFormat:@"Sentry sentry_version=%@,sentry_timestamp=%lld,sentry_key=%@,sentry_secret=%@,sentry_client=%@",
                                         SentryProtocolVersion, (long long)[self.timestamp timeIntervalSince1970], self.raven.sentryKey, self.raven.sentrySecret, TeakSentryClient]
      forHTTPHeaderField:@"X-Sentry-Auth"];
  [request setHTTPMethod:@"POST"];
  [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[payloadData length]] forHTTPHeaderField:@"Content-Length"];
  [request setHTTPBody:payloadData];

  [[[Teak URLSessionWithoutDelegate] dataTaskWithRequest:request
                                       completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                                         NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
                                         NSInteger statusCode = httpResponse.statusCode;
                                         if (statusCode >= 200 && statusCode < 300) {
                                           NSString* responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                           TeakLog_i(@"exception.reported", responseString);
                                         }
                                       }] resume];
}

+ (NSDateFormatter*)dateFormatter {
  static NSDateFormatter* dateFormatter;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSTimeZone* timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setTimeZone:timeZone];
    [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss"];
  });
  return dateFormatter;
}

@end

@implementation TeakRavenLocationHelper

+ (NSMutableArray*)helperStack {
  NSMutableDictionary* threadDictionary = [[NSThread currentThread] threadDictionary];
  NSMutableArray* helperStack = threadDictionary[@"TeakRavenLocationHelperStack"];
  if (helperStack == nil) {
    helperStack = [[NSMutableArray alloc] init];
    threadDictionary[@"TeakRavenLocationHelperStack"] = helperStack;
  }
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
  if (self) {
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
  if (data != nil) [fullData addEntriesFromDictionary:data];

  NSMutableDictionary* breadcrumb = [NSMutableDictionary dictionaryWithDictionary:@{
    @"timestamp" : [NSNumber numberWithDouble:[[[NSDate alloc] init] timeIntervalSince1970]],
    @"category" : category == nil ? @"unknown" : category,
    @"data" : fullData
  }];

  if (message != nil) [breadcrumb setValue:message forKey:@"message"];

  [self.breadcrumbs addObject:breadcrumb];
}

@end
