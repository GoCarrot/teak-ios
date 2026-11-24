#import <XCTest/XCTest.h>
#import <objc/runtime.h>

#import "TeakRequest+Internal.h"
#import "TeakSession.h"
#import "TeakSessionFixtures.h"
#import "TeakUserProfile.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

extern NSString* Teak_StringToSign(NSString* method, NSString* path, NSDictionary* payload, NSString* hostname, NSString* apiKey);

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
- (BOOL)retryTest_transmitSend:(TeakRequestSend*)send;
@end

// Test-only swizzle on the real -transmitSend:: records which send would have gone on the wire
// instead of hitting the network. Everything above it -- -send, the subclass overrides,
// -response:payload:withError:forSend:, the retry gates -- is production code.
static NSMutableArray<TeakRequestSend*>* retryTest_transmits;

@implementation TeakRequest (RetryResendTest)
- (BOOL)retryTest_transmitSend:(TeakRequestSend*)send {
  @synchronized(retryTest_transmits) {
    [retryTest_transmits addObject:send];
  }
  return YES;
}
@end

@interface TeakRequestRetryResendTests : XCTestCase
@end

@implementation TeakRequestRetryResendTests

#pragma mark - Swizzle install/remove

+ (void)swapTransmit {
  Class cls = [TeakRequest class];
  method_exchangeImplementations(class_getInstanceMethod(cls, @selector(transmitSend:)),
                                 class_getInstanceMethod(cls, @selector(retryTest_transmitSend:)));
}

- (void)setUp {
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
  return [self makeMockSessionWithLadder:@[ @0 ]];
}

- (TeakSession*)makeMockSessionWithLadder:(NSArray*)times {
  NSDictionary* ladder = @{@"retry" : @{@"times" : times, @"jitter" : @0}};
  return [TeakSessionFixtures mockSessionWithEndpointConfigurations:@{
    @"gocarrot.com" : @{@"/me/events" : ladder, @"/me/profile" : ladder}
  }];
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

- (NSError*)socketError {
  return [NSError errorWithDomain:NSPOSIXErrorDomain code:ECONNABORTED userInfo:nil];
}

// The request_id inside the body that would have gone on the wire.
- (NSString*)wireRequestIdOf:(TeakRequestSend*)send {
  NSDictionary* body = [NSJSONSerialization JSONObjectWithData:send.urlRequest.HTTPBody options:0 error:nil];
  return body[@"request_id"];
}

#pragma mark - Counting

// Every transmission of `request`, retries included, oldest first.
- (NSArray<TeakRequestSend*>*)transmitsFor:(TeakRequest*)request {
  @synchronized(retryTest_transmits) {
    return [retryTest_transmits filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(TeakRequestSend* send, NSDictionary* _) {
      return send.request == request;
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

// Hands a reply to the most recent transmission the way the URL delegate does. Returns
// immediately; the retry decision runs asynchronously, so callers wait with
// -waitForTransmits:of:timeout:.
- (void)deliver:(TeakRequest*)request status:(NSInteger)status error:(NSError*)error {
  [self deliver:request status:status error:error forSend:[self transmitsFor:request].lastObject];
}

- (void)deliver:(TeakRequest*)request status:(NSInteger)status error:(NSError*)error forSend:(TeakRequestSend*)send {
  [request response:status == 0 ? nil : [self responseWithStatus:status]
            payload:@{}
          withError:error
            forSend:send];
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

// A retry resends what the send froze. The profile's payload is rebuilt by every -send, so a retry
// that rebuilt from the live request would go out with whatever a later send had put there.
- (void)testRetryResendsTheFrozenSendNotTheLiveRequest {
  TeakUserProfile* profile = [self makeProfile];
  [self sendProfile:profile value:@"a" expectingTransmits:1];
  TeakRequestSend* original = [self transmitsFor:profile].firstObject;
  NSData* originalBody = original.urlRequest.HTTPBody;

  profile.payload = @{@"replaced" : @YES};
  [self deliver:profile status:503 error:nil];
  XCTAssertEqual([self waitForTransmits:2 of:profile timeout:3.0], 2u);

  TeakRequestSend* retry = [self transmitsFor:profile].lastObject;
  XCTAssertEqual(retry, original, @"a retry built a new send instead of resending the first");
  XCTAssertEqualObjects(retry.urlRequest.HTTPBody, originalBody);
  XCTAssertEqualObjects(retry.payload[@"string_attributes"], original.payload[@"string_attributes"]);
}

#pragma mark - Profile send order

- (NSString*)wireBodyOf:(TeakRequestSend*)send {
  return [[NSString alloc] initWithData:send.urlRequest.HTTPBody encoding:NSUTF8StringEncoding];
}

- (NSDictionary*)wireJSONOf:(TeakRequestSend*)send {
  return [NSJSONSerialization JSONObjectWithData:send.urlRequest.HTTPBody options:0 error:nil];
}

// The server orders writes by profile_seq, so two sends that overlap on the wire have to carry
// increasing numbers, as JSON integers.
- (void)testOverlappingSendsCarryIncreasingProfileSeq {
  TeakUserProfile* profile = [self makeProfile];
  [self sendProfile:profile value:@"a" expectingTransmits:1];
  [self sendProfile:profile value:@"b" expectingTransmits:2];

  NSArray<TeakRequestSend*>* sends = [self transmitsFor:profile];
  XCTAssertEqualObjects([self wireJSONOf:sends[0]][@"profile_seq"], @1);
  XCTAssertEqualObjects([self wireJSONOf:sends[1]][@"profile_seq"], @2);
  XCTAssertTrue([[self wireBodyOf:sends[0]] containsString:@"\"profile_seq\":1"], @"profile_seq was not an integer on the wire");
}

// The number belongs to the payload, not the attempt: a retry resends the same one.
- (void)testRetryKeepsItsProfileSeq {
  TeakUserProfile* profile = [self makeProfile];
  [self sendProfile:profile value:@"a" expectingTransmits:1];
  [self deliver:profile status:503 error:nil];
  XCTAssertEqual([self waitForTransmits:2 of:profile timeout:3.0], 2u);
  [self deliver:profile status:0 error:[self socketError]];
  XCTAssertEqual([self waitForTransmits:3 of:profile timeout:4.0], 3u);

  for (TeakRequestSend* attempt in [self transmitsFor:profile]) {
    XCTAssertEqualObjects([self wireJSONOf:attempt][@"profile_seq"], @1);
  }

  // The next payload is the next number, whatever the retries did.
  [self sendProfile:profile value:@"b" expectingTransmits:4];
  XCTAssertEqualObjects([self wireJSONOf:[self transmitsFor:profile].lastObject][@"profile_seq"], @2);
}

// The server verifies a signature over the context, so it goes back as the same string users.json
// sent, not a re-built dictionary.
- (void)testContextGoesOutAsTheExactStringItArrivedAs {
  NSString* context = @"{\"string\":{\"k\":null},\"number\":{},\"profile_id\":\"p1\",\"write_epoch\":\"0f1e2d3c4b5a69788796a5b4c3d2e1f0\",\"sig\":\"Ab+/=\"}";
  TeakUserProfile* profile = [[TeakUserProfile alloc] initForSession:[self makeMockSession]
                                                      withDictionary:@{
                                                        @"string_attributes" : @{@"k" : [NSNull null]},
                                                        @"number_attributes" : @{},
                                                        @"context" : context
                                                      }];
  [self sendProfile:profile value:@"a" expectingTransmits:1];

  id sent = [self wireJSONOf:[self transmitsFor:profile].firstObject][@"context"];
  XCTAssertTrue([sent isKindOfClass:[NSString class]], @"context was not sent as a string");
  XCTAssertEqualObjects(sent, context);
}

#pragma mark - A new profile send cancels the last one

// Both sends are in flight when the second starts; the first is cancelled, the second isn't.
- (void)testNewProfileSendCancelsTheLastSend {
  TeakUserProfile* profile = [self makeProfile];
  [self sendProfile:profile value:@"a" expectingTransmits:1];
  [self sendProfile:profile value:@"b" expectingTransmits:2];

  NSArray<TeakRequestSend*>* sends = [self transmitsFor:profile];
  XCTAssertTrue(sends[0].cancelled);
  XCTAssertFalse(sends[1].cancelled);
}

// The attempt A has in flight is cancelled when B starts, rather than left to land after B.
- (void)testNewProfileSendCancelsTheLastSendsTask {
  TeakUserProfile* profile = [self makeProfile];
  [self sendProfile:profile value:@"a" expectingTransmits:1];
  NSURLSessionDataTask* inFlight = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:@"https://localhost.invalid"]];
  [self transmitsFor:profile].firstObject.task = inFlight;

  [self sendProfile:profile value:@"b" expectingTransmits:2];

  XCTAssertNotEqual(inFlight.state, NSURLSessionTaskStateSuspended, @"the earlier send's task was left running");
}

// A retry waiting to fire when the next send starts must not fire: it would put the older
// payload on the wire after the newer one.
- (void)testPendingRetryOfACancelledSendIsDropped {
  // A one second ladder leaves the second send room to start well before the retry is due,
  // even on a loaded machine.
  TeakUserProfile* profile = [self makeProfileWithSession:[self makeMockSessionWithLadder:@[ @1.0 ]]];
  [self sendProfile:profile value:@"a" expectingTransmits:1];
  [self deliver:profile status:503 error:nil];
  // Let the retry be scheduled, without letting it fire.
  [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
  XCTAssertEqual([self transmitsFor:profile].count, 1u);

  [self sendProfile:profile value:@"b" expectingTransmits:2];

  // Past the point where the retry was due.
  [self waitForTransmits:NSUIntegerMax of:profile timeout:1.2];
  XCTAssertEqual([self transmitsFor:profile].count, 2u, @"the cancelled send's retry went out");
}

// A cancelled send never goes on the wire, even if something transmits it afterwards.
// Runs the real -transmitSend: (the swizzle leaves it under -retryTest_transmitSend:). Aimed at a
// host that can't resolve, so a send that wrongly got through goes nowhere.
- (void)testTransmitSendSkipsACancelledSend {
  TeakRequest* request = [self makePlainRequest];
  request.hostname = @"localhost.invalid";
  TeakRequestSend* send = [[TeakRequestSend alloc] initWithRequest:request];
  [send cancel];

  [request retryTest_transmitSend:send];

  XCTAssertNil(send.task, @"a cancelled send was started");
}

// A reply to the cancelled send that arrives after the newer send's own is not retried, and
// doesn't touch the newer send's retry budget.
- (void)testLateFailedReplyToACancelledSendIsNotRetried {
  TeakUserProfile* profile = [self makeProfile];
  [self sendProfile:profile value:@"a" expectingTransmits:1];
  [self sendProfile:profile value:@"b" expectingTransmits:2];
  NSArray<TeakRequestSend*>* sends = [self transmitsFor:profile];

  [self deliver:profile status:200 error:nil forSend:sends[1]];
  [self deliver:profile status:503 error:nil forSend:sends[0]];

  XCTAssertEqual([self settledTransmitsOf:profile], 2u, @"a stale failure was retried");
  XCTAssertEqual(sends[0].serverErrorRetries, 0u);
  XCTAssertEqual(sends[1].serverErrorRetries, 0u);
}

// Only the profile knows its sends are complete, so only it cancels the last one. A request
// that is simply sent again leaves the earlier send alone.
- (void)testSendingAPlainRequestAgainDoesNotCancelTheLastSend {
  TeakRequest* plain = [self makePlainRequest];
  [plain send];
  [plain send];

  NSArray<TeakRequestSend*>* sends = [self transmitsFor:plain];
  XCTAssertEqual(sends.count, 2u);
  XCTAssertFalse(sends[0].cancelled, @"the base class cancelled the earlier send");
}

// The session-end flush calls -send whether or not an update is pending. With none, nothing
// replaces the send that is in flight, so it must not be cancelled.
- (void)testFlushWithNothingPendingLeavesTheSendInFlight {
  TeakUserProfile* profile = [self makeProfile];
  [self sendProfile:profile value:@"a" expectingTransmits:1];
  TeakRequestSend* inFlight = [self transmitsFor:profile].firstObject;

  [profile send];
  XCTAssertEqual([self settledTransmitsOf:profile], 1u, @"a flush with nothing pending transmitted");
  XCTAssertFalse(inFlight.cancelled, @"a flush with nothing pending cancelled the send in flight");

  // And it still retries like any other send.
  [self deliver:profile status:503 error:nil];
  XCTAssertEqual([self waitForTransmits:2 of:profile timeout:3.0], 2u);
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
    TeakRequestSend* send = [self transmitsFor:request].firstObject;
    XCTAssertGreaterThan(send.requestId.length, 0u);
    XCTAssertEqualObjects([self wireRequestIdOf:send], send.requestId, @"%@ did not send its request_id", request.endpoint);
  }
}

// The signature has to cover the payload that goes out, request_id included.
- (void)testSignatureCoversTheFrozenPayload {
  TeakRequest* plain = [self makePlainRequest];
  [plain send];
  TeakRequestSend* send = [self transmitsFor:plain].firstObject;

  XCTAssertNotNil(send.payload[@"request_id"]);
  XCTAssertEqualObjects(send.stringToSign, Teak_StringToSign(plain.method, plain.endpoint, send.payload, plain.hostname, nil));
}

// A retry is the same logical request, so it has to carry the same id.
- (void)testRetriesResendTheSameRequestId {
  TeakUserProfile* profile = [self makeProfile];
  [self sendProfile:profile value:@"a" expectingTransmits:1];
  [self deliver:profile status:503 error:nil];
  XCTAssertEqual([self waitForTransmits:2 of:profile timeout:3.0], 2u);

  NSArray<TeakRequestSend*>* sends = [self transmitsFor:profile];
  XCTAssertTrue([[self wireRequestIdOf:sends[0]] isKindOfClass:[NSString class]], @"no request_id on the wire");
  XCTAssertEqualObjects([self wireRequestIdOf:sends[0]], [self wireRequestIdOf:sends[1]], @"a retry went out with a different request_id");
}

// The profile object is re-sent all session; an id reused across sends would let a
// deduping server drop every update after the first.
- (void)testEachProfileSendGetsAFreshRequestId {
  TeakUserProfile* profile = [self makeProfile];
  [self sendProfile:profile value:@"a" expectingTransmits:1];
  [self sendProfile:profile value:@"b" expectingTransmits:2];

  NSArray<TeakRequestSend*>* sends = [self transmitsFor:profile];
  XCTAssertNotEqualObjects([self wireRequestIdOf:sends[0]], [self wireRequestIdOf:sends[1]], @"two sends shared a request_id");

  // And a retry of the second send keeps the second send's id.
  [self deliver:profile status:503 error:nil];
  XCTAssertEqual([self waitForTransmits:3 of:profile timeout:3.0], 3u);
  XCTAssertEqualObjects([self wireRequestIdOf:[self transmitsFor:profile][2]], [self wireRequestIdOf:sends[1]]);
}

#pragma mark - What retries

// A reply with a status below 500 is an answer, not a failure to retry.
- (void)testHttpErrorWithoutLadderIsNotRetried {
  TeakRequest* request = [self makePlainRequest];
  [request send];
  XCTAssertEqual([self waitForTransmits:1 of:request timeout:3.0], 1u);

  [self deliver:request status:404 error:nil];

  XCTAssertEqual([self settledTransmitsOf:request], 1u);
}

// Only a 5xx reply climbs the ladder: after the one no-response retry, a configured ladder
// ([0] here) must not retry the same failure again.
- (void)testNoResponseFailureDoesNotClimbTheLadder {
  TeakBatchedRequest* batch = [self sendBatchedEvent];
  XCTAssertEqual([self waitForTransmits:1 of:batch timeout:3.0], 1u);

  [self deliver:batch status:0 error:[self urlError:NSURLErrorTimedOut]];
  XCTAssertEqual([self waitForTransmits:2 of:batch timeout:4.0], 2u);

  [self deliver:batch status:0 error:[self urlError:NSURLErrorTimedOut]];
  XCTAssertEqual([self settledTransmitsOf:batch], 2u, @"the ladder retried a request that got no reply");
}

#pragma mark - No-response failures

- (void)testProfileRetriesAfterNoResponseFailures {
  for (NSNumber* code in @[ @(NSURLErrorTimedOut), @(NSURLErrorNetworkConnectionLost) ]) {
    TeakUserProfile* profile = [self makeProfile];
    [self sendProfile:profile value:@"a" expectingTransmits:1];

    [self deliver:profile status:0 error:[self urlError:code.integerValue]];

    XCTAssertEqual([self waitForTransmits:2 of:profile timeout:4.0], 2u, @"no retry after error %@", code);
    NSArray<TeakRequestSend*>* sends = [self transmitsFor:profile];
    XCTAssertEqualObjects([self wireRequestIdOf:sends[0]], [self wireRequestIdOf:sends[1]]);
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
    NSArray<TeakRequestSend*>* sends = [self transmitsFor:batch];
    XCTAssertEqualObjects([self wireRequestIdOf:sends[0]], [self wireRequestIdOf:sends[1]], @"the batch resend carried a different request_id");
  }
}

@end
