#import "TeakLog.h"
#import "Teak+Internal.h"
#import "TeakAppConfiguration.h"
#import "TeakDataCollectionConfiguration.h"
#import "TeakDeviceConfiguration.h"
#import "TeakRaven.h"
#import "TeakRemoteConfiguration.h"

#import <libkern/OSAtomic.h>
#import <stdatomic.h>

#import "TeakHelpers.h"

NSString* INFO = @"INFO";
NSString* ERROR = @"ERROR";

extern BOOL Teak_isProductionBuild(void);

#define kTeakLogTrace @"TeakLogTrace"

__attribute__((overloadable)) void TeakLog_t(NSString* _Nonnull method, NSDictionary* _Nullable eventData) {
  static BOOL logTrace = NO;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
#define IS_FEATURE_ENABLED(_feature) ([[[NSBundle mainBundle] infoDictionary] objectForKey:_feature] == nil) ? NO : [[[[NSBundle mainBundle] infoDictionary] objectForKey:_feature] boolValue]
    logTrace = IS_FEATURE_ENABLED(kTeakLogTrace);
#undef IS_FEATURE_ENABLED
  });

  if (!logTrace) {
    return;
  }

  NSMutableDictionary* traceData = [NSMutableDictionary dictionaryWithDictionary:eventData];
  traceData[@"method"] = method;
  TeakLog_i(@"trace", traceData);
}

__attribute__((overloadable)) void TeakLog_e(NSString* eventType) {
  TeakLog_e(eventType, nil, nil);
}

__attribute__((overloadable)) void TeakLog_e(NSString* eventType, NSString* message) {
  TeakLog_e(eventType, message, nil);
}

extern __attribute__((overloadable)) void TeakLog_e(NSString* _Nonnull eventType, NSDictionary* _Nullable eventData) {
  TeakLog_e(eventType, nil, eventData);
}

__attribute__((overloadable)) void TeakLog_e(NSString* eventType, NSError* error) {
  NSDictionary* payload = @{
    @"errorDomain": error.domain,
    @"errorCode": [NSNumber numberWithLong:error.code]
  };
    TeakLog_e(eventType, [error localizedDescription], payload);
}

__attribute__((overloadable)) void TeakLog_e(NSString* eventType, NSString* message, NSDictionary* eventData) {
  NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithDictionary:eventData == nil ? @{} : eventData];
  if (message != nil) {
    [payload setValue:message forKey:@"message"];
  }
  [[Teak sharedInstance].log logEvent:eventType level:ERROR eventData:payload];
}

__attribute__((overloadable)) void TeakLog_i(NSString* eventType) {
  TeakLog_i(eventType, nil, nil);
}

__attribute__((overloadable)) void TeakLog_i(NSString* _Nonnull eventType, NSDictionary* _Nullable eventData) {
  TeakLog_i(eventType, nil, eventData);
}

__attribute__((overloadable)) void TeakLog_i(NSString* eventType, NSString* message) {
  TeakLog_i(eventType, message, nil);
}

__attribute__((overloadable)) void TeakLog_i(NSString* eventType, NSString* message, NSDictionary* eventData) {
  NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithDictionary:eventData == nil ? @{} : eventData];
  if (message != nil) {
    [payload setValue:message forKey:@"message"];
  }
  [[Teak sharedInstance].log logEvent:eventType level:INFO eventData:payload];
}

@interface TeakLog ()
@property (weak, nonatomic) Teak* teak;
@property (strong, nonatomic) NSDictionary* sdkVersion;
@property (strong, nonatomic) NSDictionary* xcodeVersion;
@property (strong, nonatomic) NSString* appId;
@property (strong, nonatomic) TeakDeviceConfiguration* deviceConfiguration;
@property (strong, nonatomic) TeakAppConfiguration* appConfiguration;
@property (strong, nonatomic) TeakRemoteConfiguration* remoteConfiguration;
@property (strong, nonatomic) TeakDataCollectionConfiguration* dataCollectionConfiguration;

@property (strong, nonatomic) NSString* runId;
@property (nonatomic) volatile atomic_uint_fast64_t eventCounter;
@end

@interface TeakLogSender : NSObject
- (void)sendData:(NSData*)data toEndpoint:(NSURL*)endpoint;
@end

@implementation TeakLog

- (nullable id)initForTeak:(nonnull Teak*)teak withAppId:(nonnull NSString*)appId {
  self = [super init];
  if (self) {
    CFUUIDRef theUUID = CFUUIDCreate(NULL);
    CFStringRef string = CFUUIDCreateString(NULL, theUUID);
    CFRelease(theUUID);
    self.runId = [(__bridge NSString*)string stringByReplacingOccurrencesOfString:@"-" withString:@""];
    CFRelease(string);

    self.eventCounter = 0;
    self.appId = appId;
    self.teak = teak;
  }
  return self;
}

- (void)useSdk:(nonnull NSDictionary*)sdkVersion andXcode:(nonnull NSDictionary*)xcodeVersion {
  self.sdkVersion = sdkVersion;
  self.xcodeVersion = xcodeVersion;

  // Log ISO8601 format timestamp at init
  NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
  [formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
  formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
  [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
  NSString* iso8601String = [formatter stringFromDate:[NSDate date]];

  [self logEvent:@"sdk_init" level:INFO eventData:@{@"at" : iso8601String}];
}

- (void)useDeviceConfiguration:(nonnull TeakDeviceConfiguration*)deviceConfiguration {
  [self logEvent:@"configuration.device" level:INFO eventData:[deviceConfiguration to_h]];
  self.deviceConfiguration = deviceConfiguration;
}

- (void)useAppConfiguration:(nonnull TeakAppConfiguration*)appConfiguration {
  [self logEvent:@"configuration.app" level:INFO eventData:[appConfiguration to_h]];
  self.appConfiguration = appConfiguration;
}

- (void)useRemoteConfiguration:(nonnull TeakRemoteConfiguration*)remoteConfiguration {
  [self logEvent:@"configuration.remote" level:INFO eventData:[remoteConfiguration to_h]];
  self.remoteConfiguration = remoteConfiguration;
}

- (void)useDataCollectionConfiguration:(nonnull TeakDataCollectionConfiguration*)dataCollectionConfiguration {
  [self logEvent:@"configuration.data_collection" level:INFO eventData:[dataCollectionConfiguration to_h]];
  self.dataCollectionConfiguration = dataCollectionConfiguration;
}

- (void)logEvent:(nonnull NSString*)eventType level:(nonnull NSString*)logLevel eventData:(nullable NSDictionary*)eventData {
  NSMutableDictionary* payload = [[NSMutableDictionary alloc] init];
  payload[@"run_id"] = self.runId;
  payload[@"event_id"] = [NSNumber numberWithUnsignedLongLong:atomic_fetch_add(&_eventCounter, 1)];
  payload[@"timestamp"] = [NSNumber numberWithLong:[[NSDate date] timeIntervalSince1970]];
  payload[@"sdk_version"] = self.sdkVersion;
  payload[@"xcode_version"] = self.xcodeVersion;
  payload[@"app_id"] = self.appId;
  payload[@"log_level"] = logLevel;

  if (self.deviceConfiguration != nil) {
    payload[@"device_id"] = self.deviceConfiguration.deviceId;
  }

  if (self.appConfiguration != nil) {
    payload[@"bundle_id"] = self.appConfiguration.bundleId;
    ;
    payload[@"client_app_version"] = self.appConfiguration.appVersion;
    payload[@"client_app_version_name"] = self.appConfiguration.appVersionName;
  }

  payload[@"event_type"] = eventType;
  payload[@"event_data"] = eventData == nil ? @{} : eventData;

  NSError* error = nil;
  NSData* jsonData = [NSJSONSerialization dataWithJSONObject:payload
                                                     options:0
                                                       error:&error];
  if (error != nil) {
    return;
  }

  // Log to the log listener
  if (self.teak.logListener) {
    self.teak.logListener(eventType, logLevel, payload);
  }

  // Log remotely
  if ([self.teak enableRemoteLogging]) {
    NSString* urlString = nil;
    if (Teak_isProductionBuild()) {
      urlString = [NSString stringWithFormat:@"https://logs.%@/sdk.log.%@", kTeakHostname, logLevel];
    } else {
      urlString = [NSString stringWithFormat:@"https://logs.%@/dev.sdk.log.%@", kTeakHostname, logLevel];
    }
    TeakLogSender* sender = [[TeakLogSender alloc] init];
    [sender sendData:jsonData toEndpoint:[NSURL URLWithString:urlString]];
  }

  // Log locally
  if ([self.teak enableDebugOutput]) {
    NSString* jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    const static int maxLogLength = 900; // 1024 but leave space for formatting
    int numLogLines = ceil((float)[jsonString length] / (float)maxLogLength);
    if (numLogLines > 1) {
      for (int i = 0; i < numLogLines; i++) {
        NSLog(@"TeakMulti[%d-%d]: %@", i + 1, numLogLines,
              [jsonString substringWithRange:NSMakeRange(i * maxLogLength, MIN([jsonString length] - i * maxLogLength, maxLogLength))]);
      }
    } else {
      NSLog(@"Teak: %@", jsonString);
    }
  }
}
@end

@implementation TeakLogSender

- (void)sendData:(NSData*)data toEndpoint:(NSURL*)endpoint {
  [self sendData:data toEndpoint:endpoint reason:nil];
}

- (void)sendData:(NSData*)data toEndpoint:(NSURL*)endpoint reason:(NSString*)reason {
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:endpoint];

  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
  [request setValue:@"UTF-8" forHTTPHeaderField:@"Accept-Charset"];

  //[request setValue:@"gzip" forHTTPHeaderField:@"Content-Encoding"]; // TODO: gzip?
  [request setHTTPMethod:@"POST"];
  [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[data length]] forHTTPHeaderField:@"Content-Length"];
  [request setHTTPBody:data];

  NSURLSessionDataTask* dataTask = [[Teak URLSessionWithoutDelegate]
      dataTaskWithRequest:request
        completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
          // When there is an error with the NSPOSIXErrorDomain domain, and the code is 53
          // this is iOS 12 coming back from the background and failing network requests.
          if (error && error.domain == NSPOSIXErrorDomain && error.code == 53 && reason == nil) {
            __weak typeof(self) weakSelf = self;
            double delayInSeconds = 1.5;
            dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
            dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul), ^(void) {
              [weakSelf sendData:data toEndpoint:endpoint reason:@"ios12_retry"];
            });
          }
        }];
  [dataTask resume];
}

@end
