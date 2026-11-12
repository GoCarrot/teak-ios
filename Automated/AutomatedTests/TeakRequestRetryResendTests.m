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
@property (nonatomic) BOOL sent;
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
// -response:payload:withError:, the retry gates, -retryTransmitForGeneration: -- is production code.
static NSMutableArray<NSDictionary*>* retryTest_transmits;

@implementation TeakRequest (RetryResendTest)
- (void)retryTest_transmit {
  const char* label = dispatch_queue_get_label(DISPATCH_CURRENT_QUEUE_LABEL);
  BOOL onOperationQueue = strcmp(label, dispatch_queue_get_label([Teak operationQueue])) == 0;
  @synchronized(retryTest_transmits) {
    [retryTest_transmits addObject:@{
      // An address, not an object: a late retry can record a request its test has already
      // released, and reading it back as an object would retain freed memory.
      @"request" : [NSValue valueWithPointer:(__bridge const void*)self],
      @"wireRequestId" : self.payload[@"request_id"] ?: [NSNull null],
      @"onOperationQueue" : @(onOperationQueue)
    }];
  }
}
@end

@interface TeakRequestRetryResendTests : XCTestCase
@end

@implementation TeakRequestRetryResendTests {
  NSDictionary* savedVersionDict;
}

#pragma mark - Swizzle install/remove

+ (void)swapTransmit {
  Class cls = [TeakRequest class];
  method_exchangeImplementations(class_getInstanceMethod(cls, @selector(transmit)),
                                 class_getInstanceMethod(cls, @selector(retryTest_transmit)));
}

- (void)setUp {
  savedVersionDict = TeakVersionDict;
  TeakVersionDict = @{@"sdk_version" : @"4.3.18-test"};
  retryTest_transmits = [NSMutableArray array];
  [TeakRequestRetryResendTests swapTransmit];
}

- (void)tearDown {
  [TeakRequestRetryResendTests swapTransmit];
  TeakVersionDict = savedVersionDict;
}

#pragma mark - Fixtures

// Retry ladder of [0] on both endpoints so a 5xx retry fires immediately; no batching
// config, so sends go out immediately.
- (TeakSession*)makeMockSession {
  return [self makeMockSessionWithLadder:@[ @0 ]];
}

- (TeakSession*)makeMockSessionWithLadder:(NSArray*)times {
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
  NSDictionary* ladder = @{@"retry" : @{@"times" : times, @"jitter" : @0}};
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
  return [self makeProfileWithSession:[self makeMockSession]];
}

- (TeakUserProfile*)makeProfileWithSession:(TeakSession*)session {
  return [[TeakUserProfile alloc] initForSession:session
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
  // The current batch is process-wide. Retire one an earlier test class left unsent (it
  // carries that test's endpoint config, not this one's) so this event starts a fresh batch.
  if (!batch.sent) {
    [batch prepareAndSend];
    batch = [TeakTrackEventBatchedRequest currentBatchForSession:session];
  }
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

- (NSError*)urlError:(NSInteger)code {
  return [NSError errorWithDomain:NSURLErrorDomain code:code userInfo:nil];
}

- (TeakRequest*)makePlainRequest {
  return [TeakRequest requestWithSession:[self makeMockSession]
                             forEndpoint:@"/me/other"
                             withPayload:@{}
                                  method:TeakRequest_POST
                                callback:nil];
}

- (NSArray<NSString*>*)wireRequestIdsOf:(TeakRequest*)request {
  return [[self transmitsFor:request] valueForKey:@"wireRequestId"];
}

- (NSError*)socketError {
  return [NSError errorWithDomain:NSPOSIXErrorDomain code:ECONNABORTED userInfo:nil];
}

#pragma mark - Counting

- (NSArray<NSDictionary*>*)transmitsFor:(TeakRequest*)request {
  @synchronized(retryTest_transmits) {
    return [retryTest_transmits filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary* transmit, NSDictionary* _) {
      return [transmit[@"request"] pointerValue] == (__bridge const void*)request;
    }]];
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

// Hands a reply to the request the way the URL delegate does. Returns immediately; the
// retry decision runs asynchronously, so callers wait with -waitForTransmits:of:timeout:.
- (void)deliver:(TeakRequest*)request status:(NSInteger)status error:(NSError*)error {
  [request response:status == 0 ? nil : [self responseWithStatus:status] payload:@{} withError:error];
}

// The retry decision runs asynchronously after -deliver:. Give it time to schedule its retry,
// so a following send meets a retry that is already pending, not one never scheduled.
- (void)letRetryDecisionRun {
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
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

#pragma mark - A newer send supersedes an earlier one

// A retry resends the request's current payload, so one that outlived a newer send would
// put that send on the wire twice. The newer send is the only one that may retry.
- (void)testNewerProfileSendDropsTheEarlierSendsPendingRetry {
  TeakUserProfile* profile = [self makeProfile];
  [self sendProfile:profile value:@"a" expectingTransmits:1];
  [self deliver:profile status:0 error:[self socketError]];
  [self letRetryDecisionRun];

  // Send B starts while A's retry is still waiting out its delay.
  [self sendProfile:profile value:@"b" expectingTransmits:2];

  XCTAssertEqual([self settledTransmitsOf:profile], 2u, @"A's retry fired after B started");
  [self waitForTransmits:NSUIntegerMax of:profile timeout:1.5];
  NSArray* ids = [self wireRequestIdsOf:profile];
  XCTAssertEqual(ids.count, 2u, @"A's retry fired after B started");
  XCTAssertNotEqualObjects(ids[0], ids[1]);

  // B still retries like any send.
  [self deliver:profile status:0 error:[self socketError]];
  XCTAssertEqual([self waitForTransmits:3 of:profile timeout:4.0], 3u, @"B lost its own retry");
  XCTAssertEqualObjects([self wireRequestIdsOf:profile][2], ids[1]);
}

- (void)testNewerProfileSendDropsTheEarlierSendsPendingServerErrorRetry {
  // A 1s ladder, so the retry is still pending when B starts.
  TeakUserProfile* profile = [self makeProfileWithSession:[self makeMockSessionWithLadder:@[ @1.0 ]]];
  [self sendProfile:profile value:@"a" expectingTransmits:1];
  [self deliver:profile status:503 error:nil];
  [self letRetryDecisionRun];

  [self sendProfile:profile value:@"b" expectingTransmits:2];

  [self waitForTransmits:NSUIntegerMax of:profile timeout:2.0];
  XCTAssertEqual([self transmitsFor:profile].count, 2u, @"A's server-error retry fired after B started");
}

// A's failure can arrive after B has started: it must not schedule a retry of B's payload or
// spend B's retry budget.
- (void)testFailureOfAnEarlierSendDoesNotRetryTheNewerSend {
  for (NSNumber* status in @[ @0, @503 ]) {
    TeakUserProfile* profile = [self makeProfile];
    [self sendProfile:profile value:@"a" expectingTransmits:1];
    NSUInteger earlier = profile.sendGeneration;
    [self sendProfile:profile value:@"b" expectingTransmits:2];

    [profile response:status.integerValue == 0 ? nil : [self responseWithStatus:status.integerValue]
              payload:@{}
            withError:status.integerValue == 0 ? [self socketError] : nil
       sendGeneration:earlier];

    XCTAssertEqual([self settledTransmitsOf:profile], 2u, @"A's failure (status %@) retried B", status);
    XCTAssertEqual(profile.socketErrorRetryCount, 0u, @"A's failure spent B's retry budget");
  }
}

#pragma mark - request_id

// The server dedupes on request_id, so it has to be in the signed payload that goes on the wire.
- (void)testRequestIdIsSentInThePayload {
  TeakUserProfile* profile = [self makeProfile];
  [self sendProfile:profile value:@"a" expectingTransmits:1];
  TeakBatchedRequest* batch = [self sendBatchedEvent];
  XCTAssertEqual([self waitForTransmits:1 of:batch timeout:3.0], 1u);
  TeakRequest* plain = [self makePlainRequest];
  [plain send];

  for (TeakRequest* request in @[ profile, batch, plain ]) {
    XCTAssertEqualObjects([self wireRequestIdsOf:request].firstObject, request.requestId, @"%@ did not send its request_id", request.endpoint);
  }
}

// A retry is the same logical request, so it has to carry the same id.
- (void)testRetriesResendTheSameRequestId {
  TeakUserProfile* profile = [self makeProfile];
  [self sendProfile:profile value:@"a" expectingTransmits:1];
  [self deliver:profile status:503 error:nil];
  XCTAssertEqual([self waitForTransmits:2 of:profile timeout:3.0], 2u);

  NSArray* ids = [self wireRequestIdsOf:profile];
  XCTAssertTrue([ids[0] isKindOfClass:[NSString class]], @"no request_id on the wire");
  XCTAssertEqualObjects(ids[0], ids[1], @"a retry went out with a different request_id");
}

// The profile object is re-sent all session; an id reused across sends would let a
// deduping server drop every update after the first.
- (void)testEachProfileSendGetsAFreshRequestId {
  TeakUserProfile* profile = [self makeProfile];
  [self sendProfile:profile value:@"a" expectingTransmits:1];
  [self sendProfile:profile value:@"b" expectingTransmits:2];

  NSArray* ids = [self wireRequestIdsOf:profile];
  XCTAssertNotEqualObjects(ids[0], ids[1], @"two sends shared a request_id");

  // And a retry of the second send keeps the second send's id.
  [self deliver:profile status:503 error:nil];
  XCTAssertEqual([self waitForTransmits:3 of:profile timeout:3.0], 3u);
  XCTAssertEqualObjects([self wireRequestIdsOf:profile][2], ids[1]);
}

#pragma mark - No-response failures

- (void)testProfileRetriesAfterNoResponseFailures {
  for (NSNumber* code in @[ @(NSURLErrorTimedOut), @(NSURLErrorNetworkConnectionLost) ]) {
    TeakUserProfile* profile = [self makeProfile];
    [self sendProfile:profile value:@"a" expectingTransmits:1];

    [self deliver:profile status:0 error:[self urlError:code.integerValue]];

    XCTAssertEqual([self waitForTransmits:2 of:profile timeout:4.0], 2u, @"no retry after error %@", code);
    NSArray* ids = [self wireRequestIdsOf:profile];
    XCTAssertEqualObjects(ids[0], ids[1]);
  }
}

- (void)testPlainRequestRetriesNoResponseOnceThenStops {
  TeakRequest* request = [self makePlainRequest];
  [request send];
  XCTAssertEqual([self waitForTransmits:1 of:request timeout:3.0], 1u);

  [self deliver:request status:0 error:[self urlError:NSURLErrorTimedOut]];
  XCTAssertEqual([self waitForTransmits:2 of:request timeout:4.0], 2u);

  // Settle past the 1.5s retry delay: a retry the stop policy should have blocked would land here.
  [self deliver:request status:0 error:[self urlError:NSURLErrorTimedOut]];
  [self waitForTransmits:NSUIntegerMax of:request timeout:2.0];
  XCTAssertEqual([self transmitsFor:request].count, 2u, @"retried past the cap");
}

- (void)testCancelledRequestIsNotRetried {
  TeakRequest* request = [self makePlainRequest];
  [request send];
  XCTAssertEqual([self waitForTransmits:1 of:request timeout:3.0], 1u);

  [self deliver:request status:0 error:[self urlError:NSURLErrorCancelled]];

  [self waitForTransmits:NSUIntegerMax of:request timeout:2.0];
  XCTAssertEqual([self transmitsFor:request].count, 1u, @"retried a cancelled request");
}

// A reply with a status is an answer, not a transport failure.
- (void)testHttpErrorWithoutLadderIsNotRetried {
  TeakRequest* request = [self makePlainRequest];
  [request send];
  XCTAssertEqual([self waitForTransmits:1 of:request timeout:3.0], 1u);

  [self deliver:request status:404 error:nil];

  [self waitForTransmits:NSUIntegerMax of:request timeout:2.0];
  XCTAssertEqual([self transmitsFor:request].count, 1u);
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

// With the server deduping /me/events on request_id, a batch is retried like any request,
// and the resend carries the same id.
- (void)testBatchedRequestRetriesNoResponseWithTheSameRequestId {
  for (NSNumber* code in @[ @(NSURLErrorNetworkConnectionLost), @(NSURLErrorTimedOut) ]) {
    TeakBatchedRequest* batch = [self sendBatchedEvent];
    XCTAssertEqual([self waitForTransmits:1 of:batch timeout:3.0], 1u);

    [self deliver:batch status:0 error:[self urlError:code.integerValue]];

    XCTAssertEqual([self waitForTransmits:2 of:batch timeout:4.0], 2u, @"no retry after error %@", code);
    NSArray* ids = [self wireRequestIdsOf:batch];
    XCTAssertEqualObjects(ids[0], ids[1], @"the batch resend carried a different request_id");
  }
}

// The send generation belongs to one request. A retry pending on batch A must survive batch B
// going out; only a later send of the same object supersedes it.
- (void)testBatchRetryIsNotDroppedWhenAnotherBatchSends {
  TeakBatchedRequest* batchA = [self sendBatchedEvent];
  XCTAssertEqual([self waitForTransmits:1 of:batchA timeout:3.0], 1u);
  [self deliver:batchA status:0 error:[self socketError]];
  [self letRetryDecisionRun];

  // Batch B goes out while A's retry is still waiting out its delay.
  TeakBatchedRequest* batchB = [self sendBatchedEvent];
  XCTAssertNotEqual(batchA, batchB, @"the second event reused the sent batch");
  XCTAssertEqual([self waitForTransmits:1 of:batchB timeout:3.0], 1u);

  XCTAssertEqual([self waitForTransmits:2 of:batchA timeout:4.0], 2u, @"batch A's retry was dropped by batch B's send");
  NSArray* ids = [self wireRequestIdsOf:batchA];
  XCTAssertEqualObjects(ids[0], ids[1], @"A's retry carried a different request_id");
  XCTAssertEqual([self settledTransmitsOf:batchB], 1u, @"batch B was retried on A's behalf");
}

@end
