#import <XCTest/XCTest.h>
#import <objc/runtime.h>

#import "TeakAppConfiguration.h"
#import "TeakDeviceConfiguration.h"
#import "TeakRemoteConfiguration.h"
#import "TeakRequest+Internal.h"
#import "TeakSession.h"
#import "TeakUserProfile.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// See TeakBatchedRequestRaceTests.m: read directly by TeakRequest's payload construction.
extern NSDictionary* TeakVersionDict;

// Private classes / methods, re-declared per the project convention.
@interface TeakBatchedRequest : TeakRequest
- (void)prepareAndSend;
+ (nullable TeakBatchedRequest*)addRequestIntoBatch:(nonnull TeakBatchedRequest*)batchedRequest
                                         withSession:(nonnull TeakSession*)session
                                         forEndpoint:(nonnull NSString*)endpoint
                                         withPayload:(nonnull NSDictionary*)payload
                                         andCallback:(nullable TeakRequestResponse)callback;
@end

@interface TeakTrackEventBatchedRequest : TeakBatchedRequest
+ (nonnull TeakTrackEventBatchedRequest*)currentBatchForSession:(nonnull TeakSession*)session;
@end

@interface TeakRequest (RetryResendTest)
- (void)response:(NSHTTPURLResponse*)response payload:(NSDictionary*)payload withError:(NSError*)error;
- (void)retryTest_transmit;
@end

@interface Teak (RetryResendTest)
+ (dispatch_queue_t _Nonnull)operationQueue;
@end

// Test-only swizzle on the real -transmit: records which request would have gone
// on the wire (and whether that happened on the operationQueue) instead of
// hitting the network. Everything above it -- -send, the subclass overrides,
// -response:payload:withError:, the retry gates, -retryTransmit -- is production code.
static NSMutableArray<NSDictionary*>* retryTest_transmits;

@implementation TeakRequest (RetryResendTest)
- (void)retryTest_transmit {
  const char* label = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
  BOOL onOperationQueue = strcmp(label, dispatch_queue_get_label([Teak operationQueue])) == 0;
  @synchronized(retryTest_transmits) {
    [retryTest_transmits addObject:@{@"requestId" : self.requestId, @"onOperationQueue" : @(onOperationQueue)}];
  }
}
@end

@interface TeakRequestRetryResendTests : XCTestCase
@end

@implementation TeakRequestRetryResendTests

#pragma mark - Swizzle install/remove

+ (void)swapTransmit {
  Class cls = [TeakRequest class];
  method_exchangeImplementations(class_getInstanceMethod(cls, @selector(transmit)),
                                 class_getInstanceMethod(cls, @selector(retryTest_transmit)));
}

- (void)setUp {
  TeakVersionDict = @{@"sdk_version" : @"4.3.18-test"};
  retryTest_transmits = [NSMutableArray array];
  [TeakRequestRetryResendTests swapTransmit];
}

- (void)tearDown {
  [TeakRequestRetryResendTests swapTransmit];
}

#pragma mark - Fixtures

// Retry ladder of [0] on both endpoints so a 5xx retry fires immediately; no batching
// config, so sends go out immediately.
- (TeakSession*)makeMockSession {
  TeakAppConfiguration* appConfig = mock([TeakAppConfiguration class]);
  [given([appConfig appId]) willReturn:@"test-app-id"];
  [given([appConfig appVersion]) willReturn:@"1"];
  [given([appConfig appVersionName]) willReturn:@"1.0.0"];
  [given([appConfig bundleId]) willReturn:@"io.teak.test"];
  [given([appConfig isProduction]) willReturn:@NO];

  TeakDeviceConfiguration* deviceConfig = mock([TeakDeviceConfiguration class]);
  [given([deviceConfig platformString]) willReturn:@"iOS"];
  [given([deviceConfig deviceModel]) willReturn:@"iPhone-test"];
  [given([deviceConfig deviceId]) willReturn:@"test-device-id"];

  TeakRemoteConfiguration* remoteConfig = mock([TeakRemoteConfiguration class]);
  NSDictionary* ladder = @{@"retry" : @{@"times" : @[ @0 ], @"jitter" : @0}};
  [given([remoteConfig endpointConfigurations]) willReturn:@{
    @"gocarrot.com" : @{@"/me/events" : ladder, @"/me/profile" : ladder}
  }];
  [given([remoteConfig dynamicParameters]) willReturn:@{}];

  TeakSession* session = mock([TeakSession class]);
  [given([session appConfiguration]) willReturn:appConfig];
  [given([session deviceConfiguration]) willReturn:deviceConfig];
  [given([session remoteConfiguration]) willReturn:remoteConfig];
  [given([session sessionId]) willReturn:@"test-session"];
  [given([session userId]) willReturn:nil];
  return session;
}

- (TeakUserProfile*)makeProfile {
  return [[TeakUserProfile alloc] initForSession:[self makeMockSession]
                                  withDictionary:@{
                                    @"string_attributes" : @{@"k" : [NSNull null]},
                                    @"number_attributes" : @{},
                                    @"context" : @"ctx"
                                  }];
}

// Builds a /me/events batch that flushes immediately (count 1, time 0) -- the
// production path through -addRequestIntoBatch: -> -prepareAndSend -> -send.
- (TeakBatchedRequest*)sendBatchedEvent {
  TeakSession* session = [self makeMockSession];
  TeakBatchedRequest* batch = [TeakTrackEventBatchedRequest currentBatchForSession:session];
  return [TeakBatchedRequest addRequestIntoBatch:batch
                                      withSession:session
                                      forEndpoint:@"/me/events"
                                      withPayload:@{@"action_type" : @"test"}
                                      andCallback:nil];
}

- (NSHTTPURLResponse*)responseWithStatus:(NSInteger)status {
  return [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://gocarrot.com"]
                                     statusCode:status
                                    HTTPVersion:@"HTTP/1.1"
                                   headerFields:@{}];
}

- (NSError*)socketError {
  return [NSError errorWithDomain:NSPOSIXErrorDomain code:ECONNABORTED userInfo:nil];
}

#pragma mark - Counting

- (NSArray<NSDictionary*>*)transmitsFor:(TeakRequest*)request {
  @synchronized(retryTest_transmits) {
    return [retryTest_transmits filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"requestId == %@", request.requestId]];
  }
}

// Spins the main run loop (retries are scheduled onto it) until `request` has been
// transmitted `count` times, or the timeout passes. Returns the final count.
- (NSUInteger)waitForTransmits:(NSUInteger)count of:(TeakRequest*)request timeout:(NSTimeInterval)timeout {
  NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
  while ([self transmitsFor:request].count < count && [deadline timeIntervalSinceNow] > 0) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
  }
  return [self transmitsFor:request].count;
}

// For "must not retry": spin long enough for any scheduled retry to have fired.
- (NSUInteger)settledTransmitsOf:(TeakRequest*)request {
  [self waitForTransmits:NSUIntegerMax of:request timeout:0.6];
  return [self transmitsFor:request].count;
}

// Sends the profile for real (one pending attribute change) and waits for the first transmit.
- (void)sendProfile:(TeakUserProfile*)profile value:(NSString*)value expectingTransmits:(NSUInteger)count {
  [profile setStringAttribute:value forKey:@"k"];
  XCTAssertEqual([self waitForTransmits:count of:profile timeout:3.0], count, @"profile -send never transmitted");
}

// Delivers `response` to the request the way the URL delegate does, and returns
// after the response handler's dispatch hop has been given time to run.
- (void)deliver:(TeakRequest*)request status:(NSInteger)status error:(NSError*)error {
  [request response:status == 0 ? nil : [self responseWithStatus:status] payload:@{} withError:error];
}

#pragma mark - TeakUserProfile

- (void)testProfileRetriesAfterSocketError {
  TeakUserProfile* profile = [self makeProfile];
  [self sendProfile:profile value:@"a" expectingTransmits:1];

  [self deliver:profile status:0 error:[self socketError]];

  XCTAssertEqual([self waitForTransmits:2 of:profile timeout:4.0], 2u, @"retry was swallowed instead of resending");
}

- (void)testProfileRetriesAfterServerError {
  TeakUserProfile* profile = [self makeProfile];
  [self sendProfile:profile value:@"a" expectingTransmits:1];

  [self deliver:profile status:503 error:nil];

  XCTAssertEqual([self waitForTransmits:2 of:profile timeout:3.0], 2u, @"retry was swallowed instead of resending");
}

// -transmit reads self.payload, which -send reassigns on the operationQueue.
- (void)testProfileRetryTransmitsOnOperationQueue {
  TeakUserProfile* profile = [self makeProfile];
  [self sendProfile:profile value:@"a" expectingTransmits:1];

  [self deliver:profile status:503 error:nil];
  XCTAssertEqual([self waitForTransmits:2 of:profile timeout:3.0], 2u);

  for (NSDictionary* transmit in [self transmitsFor:profile]) {
    XCTAssertTrue([transmit[@"onOperationQueue"] boolValue], @"every profile transmit, retries included, must run on the operationQueue");
  }
}

// Each logical send gets its own retry budget; a profile is sent many times per session.
- (void)testProfileRetryBudgetResetsOnEachSend {
  TeakUserProfile* profile = [self makeProfile];
  [self sendProfile:profile value:@"a" expectingTransmits:1];

  [self deliver:profile status:503 error:nil];
  XCTAssertEqual([self waitForTransmits:2 of:profile timeout:3.0], 2u);

  // Ladder ([0]) is now spent for this send.
  [self deliver:profile status:503 error:nil];
  XCTAssertEqual([self settledTransmitsOf:profile], 2u, @"ladder retried past its length");

  // A new attribute change starts a new logical send, which must be retryable again.
  [self sendProfile:profile value:@"b" expectingTransmits:3];
  [self deliver:profile status:503 error:nil];
  XCTAssertEqual([self waitForTransmits:4 of:profile timeout:3.0], 4u, @"later send inherited the earlier send's spent retry budget");
}

#pragma mark - TeakBatchedRequest (/me/events)

- (void)testBatchedRequestRetriesAfterSocketError {
  TeakBatchedRequest* batch = [self sendBatchedEvent];
  XCTAssertEqual([self waitForTransmits:1 of:batch timeout:3.0], 1u, @"batch never transmitted");

  [self deliver:batch status:0 error:[self socketError]];

  XCTAssertEqual([self waitForTransmits:2 of:batch timeout:4.0], 2u, @"retry hit the batch's no-op -send instead of resending");
}

- (void)testBatchedRequestRetriesAfterServerError {
  TeakBatchedRequest* batch = [self sendBatchedEvent];
  XCTAssertEqual([self waitForTransmits:1 of:batch timeout:3.0], 1u);

  [self deliver:batch status:500 error:nil];

  XCTAssertEqual([self waitForTransmits:2 of:batch timeout:3.0], 2u, @"retry hit the batch's no-op -send instead of resending");
}

// A nil response can mean the request reached the server (timeout, connection
// lost mid-transfer); re-POSTing a /me/events batch would double-count it.
- (void)testBatchedRequestDoesNotRetryNilResponseNonSocketErrors {
  NSArray<NSError*>* errors = @[
    [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNetworkConnectionLost userInfo:nil],
    [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]
  ];
  for (NSError* error in errors) {
    TeakBatchedRequest* batch = [self sendBatchedEvent];
    XCTAssertEqual([self waitForTransmits:1 of:batch timeout:3.0], 1u);

    [self deliver:batch status:0 error:error];

    XCTAssertEqual([self settledTransmitsOf:batch], 1u, @"re-sent a batch after %@", error);
  }
}

#pragma mark - Plain TeakRequest

// The retry budget still stops: one socket retry, then the reply goes to the callback.
- (void)testPlainRequestRetriesOnceThenStops {
  TeakRequest* request = [[TeakRequest alloc] initWithSession:[self makeMockSession]
                                                  forHostname:@"gocarrot.com"
                                                 withEndpoint:@"/other"
                                                  withPayload:@{}
                                                       method:TeakRequest_POST
                                                     callback:nil
                                             addCommonPayload:YES];
  [request send];
  XCTAssertEqual([self transmitsFor:request].count, 1u);

  [self deliver:request status:0 error:[self socketError]];
  XCTAssertEqual([self waitForTransmits:2 of:request timeout:4.0], 2u);

  [self deliver:request status:0 error:[self socketError]];
  XCTAssertEqual([self settledTransmitsOf:request], 2u, @"socket retry went past its stop policy");
}

@end
