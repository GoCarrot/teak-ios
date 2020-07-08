#import "Teak+Internal.h"
#import "TeakRequest+Internal.h"

#import "TeakAppConfiguration.h"
#import "TeakDeviceConfiguration.h"
#import "TeakMPInt.h"
#import "TeakRemoteConfiguration.h"
#import "TeakSession.h"

#include <CommonCrypto/CommonHMAC.h>

extern NSString* TeakHostname;
extern NSDictionary* TeakVersionDict;
extern NSString* TeakFormEncode(NSString* name, id value, BOOL escape);
extern void TeakAssignPayloadToRequest(NSMutableURLRequest* request, NSDictionary* payload);

// Helper to safe-sum NSNumbers or return the existing value, unmodified
id NSNumber_UnsignedLongLong_SafeSumOrExisting(id existing, id addition) {
  if ([existing isKindOfClass:[NSNumber class]] && [addition isKindOfClass:[NSNumber class]]) {
    NSNumber* a = existing;
    NSNumber* b = addition;
    return [NSNumber numberWithUnsignedLongLong:[a unsignedLongLongValue] + [b unsignedLongLongValue]];
  }
  return existing;
}

///// Structs to match JSON

@implementation TeakBatchConfiguration
- (TeakBatchConfiguration*)init {
  self = [super init];
  if (self) {
    self.time = 0.0f;
    self.count = 1L;
    self.maximumWaitTime = 0.0f;
  }
  return self;
}
@end

@implementation TeakRetryConfiguration
- (TeakRetryConfiguration*)init {
  self = [super init];
  if (self) {
    self.jitter = 0.0f;
    self.times = @[];
    self.retryIndex = 0;
  }
  return self;
}
@end

///// TeakBatchedRequest

@interface TeakBatchedRequest : TeakRequest
@property (strong, nonatomic) dispatch_block_t scheduledBlock;
@property (strong, nonatomic) NSMutableArray* callbacks;
@property (strong, nonatomic) NSMutableArray* batchContents;
@property (nonatomic) BOOL sent;
@property (strong, nonatomic) NSDate* _Nonnull firstAddTime;

- (void)send;               // No-op
- (void)reallyActuallySend; // Actually send

- (void)sendNow;
- (void)prepareAndSend;
- (BOOL)cancel;

+ (nullable TeakBatchedRequest*)addRequestIntoBatch:(nonnull TeakBatchedRequest*)batchedRequest withSession:(TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload andCallback:(nullable TeakRequestResponse)callback;

+ (nullable TeakBatchedRequest*)batchRequestWithSession:(TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload andCallback:(nullable TeakRequestResponse)callback;
@end

///// TeakTrackEventBatchedRequest

@interface TeakTrackEventBatchedRequest : TeakBatchedRequest
- (void)prepareAndSend;

+ (nullable TeakBatchedRequest*)batchRequestWithSession:(TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload andCallback:(nullable TeakRequestResponse)callback;

+ (BOOL)payload:(nonnull NSDictionary*)a isEqualToPayload:(nullable NSDictionary*)b;
@end

///// TeakRequestURLDelegate

@interface TeakRequestURLDelegate : NSObject <NSURLSessionTaskDelegate, NSURLSessionDataDelegate>
@property (strong, nonatomic) NSMutableDictionary* responseData;
@end

///// TeakRequest impl

NSString* TeakRequestsInFlightMutex = @"io.teak.sdk.requestsInFlightMutex";

@implementation TeakRequest

+ (NSURLSession*)sharedURLSession {
  static NSURLSession* session = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSURLSessionConfiguration* sessionConfiguration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sessionConfiguration.URLCache = nil;
    sessionConfiguration.URLCredentialStorage = nil;
    sessionConfiguration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    sessionConfiguration.HTTPAdditionalHeaders = @{@"X-Teak-DeviceType" : @"API"};
    session = [NSURLSession sessionWithConfiguration:sessionConfiguration
                                            delegate:[[TeakRequestURLDelegate alloc] init]
                                       delegateQueue:nil];

    // Srand
    srand48(time(0));
  });
  return session;
}

+ (NSMutableDictionary*)requestsInFlight {
  static NSMutableDictionary* dict = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    dict = [[NSMutableDictionary alloc] init];
  });
  return dict;
}

+ (nullable TeakRequest*)requestWithSession:(nonnull TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(nullable TeakRequestResponse)callback {
  return [TeakRequest requestWithSession:session forHostname:TeakHostname withEndpoint:endpoint withPayload:payload callback:callback];
}

+ (nullable TeakRequest*)requestWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(nullable TeakRequestResponse)callback {
  TeakRequest* ret = nil;
  if ([@"/me/events" isEqualToString:endpoint]) {
    ret = [TeakTrackEventBatchedRequest batchRequestWithSession:session forEndpoint:endpoint withPayload:payload andCallback:callback];
  } else {
    ret = [[TeakRequest alloc] initWithSession:session forHostname:hostname withEndpoint:endpoint withPayload:payload callback:callback addCommonPayload:YES];
  }
  return ret;
}

- (TeakRequest*)initWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(nullable TeakRequestResponse)callback addCommonPayload:(BOOL)addCommonToPayload {
  self = [super init];
  if (self) {
    CFUUIDRef theUUID = CFUUIDCreate(NULL);
    CFStringRef string = CFUUIDCreateString(NULL, theUUID);
    CFRelease(theUUID);
    self.requestId = [(__bridge NSString*)string stringByReplacingOccurrencesOfString:@"-" withString:@""];
    CFRelease(string);
    self.endpoint = endpoint;
    self.callback = callback;
    self.hostname = hostname;
    self.session = session;

    // Default configuration - Send imediately, no batching, no retry
    self.retry = [[TeakRetryConfiguration alloc] init];
    self.batch = [[TeakBatchConfiguration alloc] init];
    self.blackhole = NO;

    @try {
      // Assign configuration
      NSDictionary* endpointConfigurations = session.remoteConfiguration.endpointConfigurations;
      if ([endpointConfigurations[hostname] isKindOfClass:NSDictionary.class] &&
          [endpointConfigurations[hostname][endpoint] isKindOfClass:NSDictionary.class]) {
        NSDictionary* configuration = endpointConfigurations[hostname][endpoint];

        self.blackhole = [configuration[@"blackhole"] respondsToSelector:@selector(boolValue)] ? [configuration[@"blackhole"] boolValue] : self.blackhole;

        // Batching configuration
        if ([configuration[@"batch"] isKindOfClass:NSDictionary.class]) {
          self.batch.count = [configuration[@"batch"][@"count"] respondsToSelector:@selector(longValue)] ? [configuration[@"batch"][@"count"] longValue] : self.batch.count;
          self.batch.time = [configuration[@"batch"][@"time"] respondsToSelector:@selector(floatValue)] ? [configuration[@"batch"][@"time"] floatValue] : self.batch.time;
          self.batch.maximumWaitTime = [configuration[@"batch"][@"maximum_wait_time"] respondsToSelector:@selector(floatValue)] ? [configuration[@"batch"][@"maximum_wait_time"] floatValue] : self.batch.maximumWaitTime;

          // Last write wins means no maximum size, just time-based
          if ([configuration[@"batch"][@"lww"] respondsToSelector:@selector(boolValue)] &&
              [configuration[@"batch"][@"lww"] boolValue]) {
            self.batch.count = LONG_MAX;
          }
        }

        // Retry configuration
        if ([configuration[@"retry"] isKindOfClass:NSDictionary.class]) {
          self.retry.times = [configuration[@"retry"][@"times"] isKindOfClass:NSArray.class] ? configuration[@"retry"][@"times"] : self.retry.times;
          self.retry.jitter = [configuration[@"retry"][@"jitter"] respondsToSelector:@selector(floatValue)] ? [configuration[@"retry"][@"jitter"] floatValue] : self.retry.jitter;
        }
      }

      NSMutableDictionary* payloadWithCommon = [NSMutableDictionary dictionaryWithDictionary:payload];
      if (addCommonToPayload) {
        [payloadWithCommon addEntriesFromDictionary:@{
          @"appstore_name" : @"apple",
          @"game_id" : self.session.appConfiguration.appId,
          @"sdk_version" : TeakVersionDict,
          @"sdk_platform" : self.session.deviceConfiguration.platformString,
          @"app_version" : self.session.appConfiguration.appVersion,
          @"app_version_name" : self.session.appConfiguration.appVersionName,
          @"device_model" : self.session.deviceConfiguration.deviceModel,
          @"bundle_id" : self.session.appConfiguration.bundleId,
          @"device_id" : self.session.deviceConfiguration.deviceId,
          @"is_sandbox" : [NSNumber numberWithBool:!self.session.appConfiguration.isProduction]
        }];
        if (self.session.userId) {
          payloadWithCommon[@"api_key"] = self.session.userId;
        }

        // Future-Pat: save the transmission bytes
        if (!self.session.appConfiguration.isProduction) {
          payloadWithCommon[@"debug"] = [NSNumber numberWithBool:YES];
        }
      }
      self.payload = payloadWithCommon;
    } @catch (NSException* exception) {
      TeakLog_e(@"request.error.payload", @{@"error" : exception.reason});
      return nil;
    }
  }
  return self;
}

- (nonnull NSString*)stringToSign {
  NSString* path = self.endpoint;
  if (path == nil || path.length < 1) path = @"/";

  // Build query string to sign
  NSArray* queryKeysSorted = [[self.payload allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
  NSMutableArray* sortedQueryStringArray = [[NSMutableArray alloc] init];
  for (int i = 0; i < queryKeysSorted.count; i++) {
    NSString* key = queryKeysSorted[i];
    id value = self.payload[key];
    NSString* encoded = TeakFormEncode(key, value, NO);
    if ([encoded length] > 0) {
      [sortedQueryStringArray addObject:encoded];
    }
  }

  return [NSString stringWithFormat:@"%@\n%@\n%@\n%@", @"POST", self.hostname, path, [sortedQueryStringArray componentsJoinedByString:@"&"]];
}

- (nonnull NSString*)sig {
  NSString* stringToSign = [self stringToSign];

  NSData* dataToSign = [stringToSign dataUsingEncoding:NSUTF8StringEncoding];
  uint8_t digestBytes[CC_SHA256_DIGEST_LENGTH];
  CCHmac(kCCHmacAlgSHA256, [self.session.appConfiguration.apiKey UTF8String], self.session.appConfiguration.apiKey.length, [dataToSign bytes], [dataToSign length], &digestBytes);

  NSData* digestData = [NSData dataWithBytes:digestBytes length:CC_SHA256_DIGEST_LENGTH];
  return [digestData base64EncodedStringWithOptions:0];
}

- (nonnull NSDictionary*)signedPayload {
  teak_try {
    // Dictionary with 'sig' added
    NSMutableDictionary* signedPayload = [[NSMutableDictionary alloc] initWithDictionary:self.payload];
    signedPayload[@"sig"] = [self sig];

    return signedPayload;
  }
  teak_catch_report;

  return self.payload;
}

- (void)send {
  if (self.blackhole) return;

  teak_try {
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://%@%@", self.hostname, self.endpoint]]];
    NSDictionary* signedPayload = [self signedPayload];
    teak_log_data_breadcrumb(@"request.send.signedPayload", signedPayload);

    TeakAssignPayloadToRequest(request, signedPayload);
    teak_log_breadcrumb(@"request.send.constructed");

    NSURLSessionDataTask* dataTask = [[TeakRequest sharedURLSession] dataTaskWithRequest:request];
    @synchronized(TeakRequestsInFlightMutex) {
      [TeakRequest requestsInFlight][@(dataTask.taskIdentifier)] = self;
    }
    self.sendDate = [NSDate date];
    [dataTask resume];

    TeakLog_i(@"request.send", [self to_h]);
    teak_log_breadcrumb(@"request.send.sent");
  }
  teak_catch_report;
}

- (NSDictionary*)to_h {
  return @{
    @"request_id" : self.requestId,
    @"hostname" : self.hostname == nil ? [NSNull null] : self.hostname,
    @"endpoint" : self.endpoint,
    @"payload" : self.payload,
    @"session" : self.session.sessionId
  };
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<%@: %p> endpoint: %@; callback: %p; payload: %@",
                                    NSStringFromClass([self class]),
                                    self,
                                    self.endpoint,
                                    self.callback,
                                    self.payload];
}

- (void)response:(NSHTTPURLResponse*)response payload:(NSDictionary*)payload withError:(NSError*)error {
  TeakUnused(error);

  teak_try {
    NSMutableDictionary* h = [NSMutableDictionary dictionaryWithDictionary:[self to_h]];

    h[@"response_time"] = [NSNumber numberWithDouble:[self.sendDate timeIntervalSinceNow] * -1000.0];
    h[@"payload"] = payload;
    h[@"response_headers"] = response.allHeaderFields;
    TeakLog_i(@"request.reply", h);

    if (response.statusCode == 403) {
      @try {
        NSString* clientSignedString = [self stringToSign];
        NSString* serverSignedString = payload[@"string_to_sign"];

        TeakLog_e(@"request.error.signature", @{
          @"client" : clientSignedString,
          @"server" : _(serverSignedString),
          @"client_signature" : [self sig]
        });
      } @finally {
      }
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      teak_try {
        if ((response == nil || response.statusCode >= 500) && self.retry.retryIndex < [self.retry.times count]) {
          // Retry with delay + jitter
          float jitter = (drand48() * 2.0 - 1.0) * self.retry.jitter;
          float delay = [self.retry.times[self.retry.retryIndex] floatValue] + jitter;
          if (delay < 0.0f) delay = 0.0f;

          self.retry.retryIndex++;

          dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC);
          dispatch_after(delayTime, dispatch_get_main_queue(), ^{
            [self send];
          });
        } else {
          // Check to see if the response has a 'report_client_error' key
          if (payload[@"report_client_error"] != nil &&
              payload[@"report_client_error"] != [NSNull null]) {

            // Catch and toss exceptions, we don't want to prevent the callback from happening
            @try {
              // We are going to get a 'message' key and optionally a 'title' key
              NSDictionary* clientError = payload[@"report_client_error"];
              NSString* title = clientError[@"title"] == nil ? clientError[@"title"] : @"Configuration Error";

              [[Teak sharedInstance].integrationChecker reportError:clientError[@"message"] forCategory:title];
            } @finally {
            }
          }

          if (self.callback) {
            self.callback(payload);
          }
        }
      }
      teak_catch_report;
    });
  }
  teak_catch_report;
}

@end

///// TeakTrackEventBatchedRequest impl

static NSString* TeakTrackEventBatchedRequestMutex = @"io.teak.sdk.trackEventBatchedRequest";

@implementation TeakTrackEventBatchedRequest

- (TeakBatchedRequest*)initWithSession:(nonnull TeakSession*)session {
  self = [super initWithSession:session
                    forHostname:TeakHostname
                   withEndpoint:@"/me/events"
                    withPayload:@{}
                       callback:^(NSDictionary* reply) {
                         // Trigger any callbacks
                         for (TeakRequestResponse callback in self.callbacks) {
                           callback(reply);
                         }
                       }
               addCommonPayload:YES];
  return self;
}

+ (TeakTrackEventBatchedRequest*)currentBatchForSession:(TeakSession*)session {
  static TeakTrackEventBatchedRequest* currentBatch = nil;
  @synchronized(TeakTrackEventBatchedRequestMutex) {
    if (currentBatch == nil || currentBatch.sent) {
      currentBatch = [[TeakTrackEventBatchedRequest alloc] initWithSession:session];
    }
  }
  return currentBatch;
}

- (void)prepareAndSend {
  @synchronized(self) {
    NSMutableDictionary* payload = [NSMutableDictionary dictionaryWithDictionary:self.payload];
    payload[@"batch"] = self.batchContents;
    payload[@"ms_since_first_event"] = [NSNumber numberWithDouble:[self.firstAddTime timeIntervalSinceNow] * -1000.0];
    self.payload = payload;
  }
  [super prepareAndSend];
}

+ (nullable TeakBatchedRequest*)batchRequestWithSession:(TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload andCallback:(nullable TeakRequestResponse)callback {
  TeakBatchedRequest* currentBatch = [TeakTrackEventBatchedRequest currentBatchForSession:session];
  currentBatch = [TeakBatchedRequest addRequestIntoBatch:currentBatch
                                             withSession:session
                                             forEndpoint:endpoint
                                             withPayload:payload
                                             andCallback:callback];
  return currentBatch;
}

+ (BOOL)payload:(nonnull NSDictionary*)a isEqualToPayload:(nullable NSDictionary*)b {
#define _HELPER_EQL(a, b) ((a == b) || (a != nil && [a isEqualToString:b]) || (b != nil && [b isEqualToString:a]))
  if (b == nil) return NO;
  if (![a[@"action_type"] isEqualToString:b[@"action_type"]]) return NO;
  if (!_HELPER_EQL(a[@"object_type"], b[@"object_type"])) return NO;
  return _HELPER_EQL(a[@"object_instance_id"], b[@"object_instance_id"]);
#undef _HELPER_EQL
}

@end

///// TeakBatchedRequest impl

@implementation TeakBatchedRequest

+ (nullable TeakBatchedRequest*)batchRequestWithSession:(TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload andCallback:(nullable TeakRequestResponse)callback {
  return nil;
}

- (TeakBatchedRequest*)initWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(nullable TeakRequestResponse)callback addCommonPayload:(BOOL)addCommonToPayload {
  self = [super initWithSession:session forHostname:hostname withEndpoint:endpoint withPayload:payload callback:callback addCommonPayload:addCommonToPayload];
  if (self) {
    self.sent = NO;
    self.callbacks = [[NSMutableArray alloc] init];
    self.batchContents = [[NSMutableArray alloc] init];

    RegisterKeyValueObserverFor(self.session, currentState);
  }
  return self;
}

- (void)dealloc {
  UnRegisterKeyValueObserverFor(self.session, currentState);
}

// Returns YES if this request will not be sent
// Returns NO if the request has already been sent or will be sent anyway
- (BOOL)cancel {
  @synchronized(self) {
    if (self.sent == YES) return NO;
    if (self.scheduledBlock == nil) return YES;

    dispatch_block_cancel(self.scheduledBlock);
    return dispatch_block_testcancel(self.scheduledBlock) != 0;
  }
}

KeyValueObserverFor(TeakBatchedRequest, TeakSession, currentState) {
  TeakUnusedKVOValues;
  @synchronized(self) {
    if (newValue == [TeakSession UserIdentified] || newValue == [TeakSession Expiring]) {
      [self sendNow];
    }
  }
}

- (void)sendNow {
  if ([self cancel]) {
    [self prepareAndSend];
  }
}

+ (nullable TeakBatchedRequest*)addRequestIntoBatch:(nonnull TeakBatchedRequest*)batchedRequest withSession:(TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload andCallback:(nullable TeakRequestResponse)callback {
  if (payload == nil || endpoint == nil || batchedRequest == nil) return batchedRequest;

  if (![batchedRequest cancel]) {
    // Future-Pat, don't forget about this reassignment and move the @synchronized
    batchedRequest = [batchedRequest.class batchRequestWithSession:session
                                                       forEndpoint:endpoint
                                                       withPayload:payload
                                                       andCallback:callback];
    if (batchedRequest == nil) return nil;
  }

  @synchronized(batchedRequest) {
    // Check for black-holed requests
    if (batchedRequest.blackhole) {
      return batchedRequest;
    }

    if (callback != nil) {
      [batchedRequest.callbacks addObject:[callback copy]];
    }

    // If this is a TrackEvent batch, see if the payload can be folded in to an
    // existing payload item.
    BOOL payloadAddedViaIncrement = NO;
    if ([@"/me/events" isEqualToString:endpoint]) {
      for (NSUInteger i = 0; i < batchedRequest.batchContents.count; i++) {
        // If the payloads are equal, smash them together
        NSDictionary* batchEntry = batchedRequest.batchContents[i];
        if ([TeakTrackEventBatchedRequest payload:payload isEqualToPayload:batchEntry]) {
          NSMutableDictionary* summedEntry = [batchEntry mutableCopy];

          summedEntry[@"duration"] = NSNumber_UnsignedLongLong_SafeSumOrExisting(summedEntry[@"duration"], payload[@"duration"]);
          summedEntry[@"count"] = NSNumber_UnsignedLongLong_SafeSumOrExisting(summedEntry[@"count"], payload[@"count"]);
          if ([summedEntry[@"sum_of_squares"] isKindOfClass:[TeakMPInt class]]) {
            [summedEntry[@"sum_of_squares"] sumWith:payload[@"sum_of_squares"]];
          }

          [batchedRequest.batchContents replaceObjectAtIndex:i
                                                  withObject:summedEntry];
          payloadAddedViaIncrement = YES;
          break;
        }
      }
    }

    // It couldn't be folded in, so append it
    if (!payloadAddedViaIncrement) {
      [batchedRequest.batchContents addObject:payload];
    }

    // If we've hit the limit, or delay time is 0.0, send now; otherwise schedule
    if (batchedRequest.batchContents.count >= batchedRequest.batch.count || batchedRequest.batch.time == 0.0f) {
      [batchedRequest prepareAndSend];
    } else {
      batchedRequest.scheduledBlock = dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, ^{
        [batchedRequest prepareAndSend];
      });

      dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, batchedRequest.batch.time * NSEC_PER_SEC);
      dispatch_after(delayTime, dispatch_get_main_queue(), batchedRequest.scheduledBlock);

      // If this is the first request added to the batch, set up the first add time
      if (batchedRequest.firstAddTime == nil) {
        batchedRequest.firstAddTime = [NSDate date];

        // If the batch configuration specifies a maximum wait time, schedule
        if (batchedRequest.batch.maximumWaitTime > 0.0f) {
          // We can't use batchedRequest.scheduledBlock because there is no difference between
          // the blocks when cancel is called.
          dispatch_time_t maxDelayTime = dispatch_time(DISPATCH_TIME_NOW, batchedRequest.batch.maximumWaitTime * NSEC_PER_SEC);
          dispatch_after(maxDelayTime, dispatch_get_main_queue(), dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, ^{
                           [batchedRequest prepareAndSend];
                         }));
        }
      }
    }
  }

  return batchedRequest;
}

- (void)send {
  // No-op
}

- (void)prepareAndSend {
  @synchronized(self) {
    if (self.sent == NO) {
      self.sent = YES;
      UnRegisterKeyValueObserverFor(self.session, currentState);

      // Sum of squares
      for (NSUInteger i = 0; i < self.batchContents.count; i++) {
        NSMutableDictionary* entry = [self.batchContents[i] mutableCopy];
        if (entry[@"sum_of_squares"]) {
          entry[@"sum_of_squares"] = [entry[@"sum_of_squares"] description];
          [self.batchContents replaceObjectAtIndex:i
                                        withObject:entry];
        }
      }
      [self reallyActuallySend];
    }
  }
}

- (void)reallyActuallySend {
  [super send];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
KeyValueObserverSupported(TeakBatchedRequest);
#pragma clang diagnostic pop

@end

///// TeakRequestURLDelegate impl

@implementation TeakRequestURLDelegate

- (id)init {
  self = [super init];
  if (self) {
    self.responseData = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)dataTask didReceiveResponse:(NSURLResponse*)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
  completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)dataTask didReceiveData:(NSData*)data {
  teak_try {
    @synchronized(self) {
      NSMutableData* responseData = self.responseData[@(dataTask.taskIdentifier)];
      if (!responseData) {
        self.responseData[@(dataTask.taskIdentifier)] = [NSMutableData dataWithData:data];
      } else {
        [responseData appendData:data];
      }
    }
  }
  teak_catch_report;
}

- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)dataTask didCompleteWithError:(NSError*)error {
  NSDictionary* reply = @{};
  if (error) {
    // TODO: Server errors don't come in here, not certain what should be handled here
  } else {
    teak_try {
      @synchronized(self) {
        NSData* data = self.responseData[@(dataTask.taskIdentifier)];
        if (data) {
          reply = (NSDictionary*)[NSJSONSerialization JSONObjectWithData:data
                                                                 options:kNilOptions
                                                                   error:&error];
        }
      }

      if (error) {
        reply = @{};
      }
    }
    teak_catch_report;
  }

  @synchronized(self) {
    [self.responseData removeObjectForKey:@(dataTask.taskIdentifier)];
  }

  @synchronized(TeakRequestsInFlightMutex) {
    TeakRequest* request = [TeakRequest requestsInFlight][@(dataTask.taskIdentifier)];
    if (request) {
      [request response:(NSHTTPURLResponse*)dataTask.response payload:reply withError:error];
      [[TeakRequest requestsInFlight] removeObjectForKey:@(dataTask.taskIdentifier)];
    }
  }
}

@end
