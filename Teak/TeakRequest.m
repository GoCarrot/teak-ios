#import "Teak+Internal.h"
#import "TeakRequest+Internal.h"

#import "TeakAppConfiguration.h"
#import "TeakDeviceConfiguration.h"
#import "TeakMPInt.h"
#import "TeakRemoteConfiguration.h"
#import "TeakSession.h"

#import "TeakHelpers.h"
#import "TeakKVOHelpers.h"

#include <CommonCrypto/CommonHMAC.h>
#include <sys/errno.h>

// Delay before retrying a request that failed with a socket-closed transport
// error. Matches TeakLog.m's TeakLogSender delayInSeconds, which retries the
// same underlying OS behavior on its own NSURLSession — tune both together.
static const NSTimeInterval TeakRequestSocketErrorRetryDelay = 1.5;

// How many times a socket-closed transport error gets retried. The stop
// policy lives here so the call site doesn't need to know the limit —
// raising it later is a one-line change.
const NSUInteger TeakRequestMaxSocketRetries = 1;

#define _(_id) TeakValueOrNSNull(_id)

NSString* _Nonnull const TeakRequest_POST = @"POST";
NSString* _Nonnull const TeakRequest_DELETE = @"DELETE";

extern NSDictionary* TeakVersionDict;
extern void TeakAssignPayloadToRequest(NSString* method, NSMutableURLRequest* request, NSDictionary* payload);
extern NSString* TeakHexStringFromData(NSData* data);

// Helper to safe-sum NSNumbers or return the existing value, unmodified
id NSNumber_UnsignedLongLong_SafeSumOrExisting(id existing, id addition) {
  if ([existing isKindOfClass:[NSNumber class]] && [addition isKindOfClass:[NSNumber class]]) {
    NSNumber* a = existing;
    NSNumber* b = addition;
    return [NSNumber numberWithUnsignedLongLong:[a unsignedLongLongValue] + [b unsignedLongLongValue]];
  }
  return existing;
}

NSString* Teak_SignData(NSData* dataToSign, NSString* apiKey) {
  uint8_t digestBytes[CC_SHA256_DIGEST_LENGTH];
  CCHmac(kCCHmacAlgSHA256, [apiKey UTF8String], apiKey.length, [dataToSign bytes], [dataToSign length], &digestBytes);

  NSData* digestData = [NSData dataWithBytes:digestBytes length:CC_SHA256_DIGEST_LENGTH];
  return TeakHexStringFromData(digestData);
}

NSString* Teak_SignString(NSString* stringToSign, NSString* apiKey) {
  NSData* dataToSign = [stringToSign dataUsingEncoding:NSUTF8StringEncoding];
  return Teak_SignData(dataToSign, apiKey);
}

// Helper to turn payload dict into string to sign
NSString* Teak_StringToSign(NSString* method, NSString* path, NSDictionary* payload, NSString* hostname, NSString* apiKey) {
  if (path == nil || path.length < 1) path = @"/";

  NSData* postData = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];

  return [NSString stringWithFormat:@"TeakV2-HMAC-SHA256\n%@\n%@\n%@\n%@\n", method, hostname, path, Teak_SignData(postData, apiKey)];
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

+ (NSDictionary*)parseJSONResponseData:(NSData*)data error:(NSError**)outError {
  if (data == nil || data.length == 0) return @{};

  NSError* parseError = nil;
  id parsed = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&parseError];
  if (parsed == nil) {
    if (outError) *outError = parseError;
    return @{};
  }
  if (![parsed isKindOfClass:[NSDictionary class]]) {
    if (outError) {
      *outError = [NSError errorWithDomain:@"io.teak.TeakRequest"
                                      code:0
                                  userInfo:@{NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Expected top-level JSON object, got %@", NSStringFromClass([parsed class])]}];
    }
    return @{};
  }
  return parsed;
}

+ (NSString*)titleForClientError:(NSDictionary*)clientError {
  id title = clientError[@"title"];
  if ([title isKindOfClass:[NSString class]]) return title;
  return @"Configuration Error";
}

+ (BOOL)isRetryableSocketError:(NSError*)error {
  if (error == nil) return NO;
  if ([error.domain isEqualToString:NSPOSIXErrorDomain] && error.code == ECONNABORTED) return YES;

  NSError* underlying = error.userInfo[NSUnderlyingErrorKey];
  if ([underlying isKindOfClass:[NSError class]] &&
      [underlying.domain isEqualToString:NSPOSIXErrorDomain] && underlying.code == ECONNABORTED) {
    return YES;
  }

  return NO;
}

+ (BOOL)shouldRetrySocketError:(NSError*)error retryCount:(NSUInteger)retryCount {
  return [TeakRequest isRetryableSocketError:error] && retryCount < TeakRequestMaxSocketRetries;
}

+ (NSMutableDictionary*)requestsInFlight {
  static NSMutableDictionary* dict = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    dict = [[NSMutableDictionary alloc] init];
  });
  return dict;
}

+ (nullable TeakRequest*)requestWithSession:(nonnull TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload method:(nonnull NSString*)method callback:(nullable TeakRequestResponse)callback {
  return [TeakRequest requestWithSession:session forHostname:kTeakHostname withEndpoint:endpoint withPayload:payload method:method callback:callback];
}

+ (nullable TeakRequest*)requestWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload method:(nonnull NSString*)method callback:(nullable TeakRequestResponse)callback {
  TeakRequest* ret = nil;
  if ([@"/me/events" isEqualToString:endpoint]) {
    // Future-Ezri: method is still being assumed here
    ret = [TeakTrackEventBatchedRequest batchRequestWithSession:session forEndpoint:endpoint withPayload:payload andCallback:callback];
  } else {
    ret = [[TeakRequest alloc] initWithSession:session forHostname:hostname withEndpoint:endpoint withPayload:payload method:method callback:callback addCommonPayload:YES];
  }
  return ret;
}

- (TeakRequest*)initWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload method:(nonnull NSString*)method callback:(nullable TeakRequestResponse)callback addCommonPayload:(BOOL)addCommonToPayload {
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
    self.method = method;
    self.socketErrorRetryCount = 0;

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
        [payloadWithCommon addEntriesFromDictionary:session.remoteConfiguration.dynamicParameters];
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
  return Teak_StringToSign(self.method, self.endpoint, self.payload, self.hostname, self.session.appConfiguration.apiKey);
}

- (nonnull NSString*)sig {
  return Teak_SignString([self stringToSign], self.session.appConfiguration.apiKey);
}

- (void)send {
  if (self.blackhole) return;

  teak_try {
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://%@%@", self.hostname, self.endpoint]]];
    TeakAssignPayloadToRequest(self.method, request, self.payload);
    [request setValue:[NSString stringWithFormat:@"TeakV2-HMAC-SHA256 Signature=%@", self.sig] forHTTPHeaderField:@"Authorization"];
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
  teak_try {
    NSMutableDictionary* h = [NSMutableDictionary dictionaryWithDictionary:[self to_h]];

    h[@"response_time"] = [NSNumber numberWithDouble:[self.sendDate timeIntervalSinceNow] * -1000.0];
    h[@"payload"] = payload;
    h[@"response_headers"] = response.allHeaderFields;
    TeakLog_i(@"request.reply", h);

    NSString* errorMetadata = payload[@"metadata"] ? payload[@"metadata"][@"string_to_sign"] : nil;

    if (response.statusCode == 403 || errorMetadata) {
      @try {
        NSString* clientSignedString = [self stringToSign];
        NSString* serverSignedString = errorMetadata ? errorMetadata : payload[@"string_to_sign"];

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
        BOOL isSocketError = [TeakRequest isRetryableSocketError:error];

        if ([TeakRequest shouldRetrySocketError:error retryCount:self.socketErrorRetryCount]) {
          // The OS can close a pooled connection's socket while the app is
          // backgrounded and fail to reopen it on the next request; retry
          // once after a short delay rather than surfacing an empty reply.
          // Checked ahead of the server-configured retry ladder below since
          // it's a distinct failure class (transport, not HTTP) — a request
          // with configured retry times still gets this one stacked on top.
          self.socketErrorRetryCount++;
          TeakLog_i(@"request.retry.socket_error", [self to_h]);

          dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, TeakRequestSocketErrorRetryDelay * NSEC_PER_SEC);
          dispatch_after(delayTime, dispatch_get_main_queue(), ^{
            [self send];
          });
        } else if ((response == nil || response.statusCode >= 500) && self.retry.retryIndex < [self.retry.times count]) {
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
          if (isSocketError) {
            TeakLog_e(@"request.retry.socket_error.exhausted", [self to_h]);
          }

          // Check to see if the response has a 'report_client_error' key
          if (payload[@"report_client_error"] != nil &&
              payload[@"report_client_error"] != [NSNull null]) {

            // Catch and toss exceptions, we don't want to prevent the callback from happening
            @try {
              // We are going to get a 'message' key and optionally a 'title' key
              NSDictionary* clientError = payload[@"report_client_error"];
              NSString* title = [TeakRequest titleForClientError:clientError];

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
                    forHostname:kTeakHostname
                   withEndpoint:@"/me/events"
                    withPayload:@{}
                         method:TeakRequest_POST
                       callback:^(NSDictionary* reply) {
                         // Snapshot under the same lock -addRequestIntoBatch: appends
                         // callbacks under, then invoke outside the lock so an
                         // arbitrary host-app callback can't deadlock against it.
                         NSArray* callbacksSnapshot;
                         @synchronized(self) {
                           callbacksSnapshot = [self.callbacks copy];
                         }
                         for (TeakRequestResponse callback in callbacksSnapshot) {
                           callback(reply);
                         }
                       }
               addCommonPayload:YES];
  return self;
}

+ (TeakTrackEventBatchedRequest*)currentBatchForSession:(TeakSession*)session {
  static TeakTrackEventBatchedRequest* currentBatch = nil;
  TeakTrackEventBatchedRequest* result;
  @synchronized(TeakTrackEventBatchedRequestMutex) {
    // .sent is written under the instance lock (-prepareAndSend), so it must be
    // read under that same lock here too -- otherwise this class-mutex-only
    // read can go stale against a concurrent send and hand out an
    // already-sent batch.
    BOOL needsNewBatch = currentBatch == nil;
    if (!needsNewBatch) {
      @synchronized(currentBatch) {
        needsNewBatch = currentBatch.sent;
      }
    }
    if (needsNewBatch) {
      currentBatch = [[TeakTrackEventBatchedRequest alloc] initWithSession:session];
    }
    // Snapshot the return value here, still under the lock -- returning
    // `currentBatch` directly after this block closes would re-read the
    // static var unsynchronized, racing a concurrent call's locked write.
    result = currentBatch;
  }
  return result;
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

- (TeakBatchedRequest*)initWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload method:(nonnull NSString*)method callback:(nullable TeakRequestResponse)callback addCommonPayload:(BOOL)addCommonToPayload {
  self = [super initWithSession:session forHostname:hostname withEndpoint:endpoint withPayload:payload method:method callback:callback addCommonPayload:addCommonToPayload];
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
  @synchronized(self) {
    if ([self cancel]) {
      [self prepareAndSend];
    }
  }
}

+ (nullable TeakBatchedRequest*)addRequestIntoBatch:(nonnull TeakBatchedRequest*)batchedRequest withSession:(TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload andCallback:(nullable TeakRequestResponse)callback {
  if (payload == nil || endpoint == nil || batchedRequest == nil) return batchedRequest;

  // -cancel and the append below run as one atomic step under this lock. A
  // KVO-driven sendNow (see currentState below) cancels+sends under this same
  // lock; if it ran between a standalone -cancel call and a later, separate
  // @synchronized block here, it could transmit the batch before this payload
  // was appended -- silently dropping it. didAppend stays false (and nothing
  // below runs) when the batch turns out to already be sent, so this thread
  // never holds this lock while also reaching for the currentBatchForSession:
  // class mutex -- see the didAppend branch below for why that ordering matters.
  BOOL didAppend = NO;
  @synchronized(batchedRequest) {
    didAppend = [batchedRequest cancel];
    if (didAppend) {
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
  }

  if (!didAppend) {
    // batchedRequest was already sent -- e.g. cancel lost a race with a
    // concurrent sendNow, or currentBatchForSession: handed out a stale
    // reference -- so it can no longer accept this payload. Fetch a fresh
    // batch and append into it instead of dropping the payload. This runs
    // with batchedRequest's lock already released: batchRequestWithSession:
    // reaches into currentBatchForSession:'s class mutex, and taking that
    // mutex while still holding an instance lock here would invert the lock
    // order against currentBatchForSession:'s own (mutex, then instance lock)
    // nesting, deadlocking against a concurrent call on the same batch.
    return [batchedRequest.class batchRequestWithSession:session
                                              forEndpoint:endpoint
                                              withPayload:payload
                                              andCallback:callback];
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
    TeakLog_e(@"request.reply.error", error);
  } else {
    teak_try {
      NSData* data = nil;
      @synchronized(self) {
        data = self.responseData[@(dataTask.taskIdentifier)];
      }
      NSError* parseError = nil;
      reply = [TeakRequest parseJSONResponseData:data error:&parseError];
      if (parseError) {
        TeakLog_e(@"request.reply.parse_error", parseError);
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
