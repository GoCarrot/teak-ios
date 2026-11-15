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
- (void)retryTest_transmitSend:(TeakRequestSend*)send;
@end

// Test-only swizzle on the real -transmitSend:: records which send would have gone on the wire
// instead of hitting the network. Everything above it -- -send, the subclass overrides,
// -response:payload:withError:forSend:, the retry gates -- is production code.
static NSMutableArray<TeakRequestSend*>* retryTest_transmits;

@implementation TeakRequest (RetryResendTest)
- (void)retryTest_transmitSend:(TeakRequestSend*)send {
  @synchronized(retryTest_transmits) {
    [retryTest_transmits addObject:send];
  }
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
  NSDictionary* ladder = @{@"retry" : @{@"times" : @[ @0 ], @"jitter" : @0}};
  return [TeakSessionFixtures mockSessionWithEndpointConfigurations:@{
    @"gocarrot.com" : @{@"/me/events" : ladder, @"/me/profile" : ladder}
  }];
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
  [request response:status == 0 ? nil : [self responseWithStatus:status]
            payload:@{}
          withError:error
            forSend:[self transmitsFor:request].lastObject];
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

// Only a 5xx reply climbs the ladder.
- (void)testNoResponseFailureDoesNotClimbTheLadder {
  TeakBatchedRequest* batch = [self sendBatchedEvent];
  XCTAssertEqual([self waitForTransmits:1 of:batch timeout:3.0], 1u);

  [self deliver:batch status:0 error:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];

  XCTAssertEqual([self settledTransmitsOf:batch], 1u);
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

@end
