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
- (void)retryTest_transmit;
@end

// Test-only swizzle on the real -transmit: records which request would have gone
// on the wire instead of hitting the network. Everything above it -- -send, the
// subclass overrides, the payload construction -- is production code.
static NSMutableArray<NSDictionary*>* retryTest_transmits;

@implementation TeakRequest (RetryResendTest)
- (void)retryTest_transmit {
  @synchronized(retryTest_transmits) {
    [retryTest_transmits addObject:@{
      // An address, not an object: a late retry can record a request its test has already
      // released, and reading it back as an object would retain freed memory.
      @"request" : [NSValue valueWithPointer:(__bridge const void*)self],
      @"wireRequestId" : self.payload[@"request_id"] ?: [NSNull null]
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

// No batching config, so sends go out immediately.
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
  [given([remoteConfig endpointConfigurations]) willReturn:@{}];
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

// Sends the profile for real (one pending attribute change) and waits for the first transmit.
- (void)sendProfile:(TeakUserProfile*)profile value:(NSString*)value expectingTransmits:(NSUInteger)count {
  [profile setStringAttribute:value forKey:@"k"];
  XCTAssertEqual([self waitForTransmits:count of:profile timeout:3.0], count, @"profile -send never transmitted");
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

// The profile object is re-sent all session; an id reused across sends would let a
// deduping server drop every update after the first.
- (void)testEachProfileSendGetsAFreshRequestId {
  TeakUserProfile* profile = [self makeProfile];
  [self sendProfile:profile value:@"a" expectingTransmits:1];
  [self sendProfile:profile value:@"b" expectingTransmits:2];

  NSArray* ids = [self wireRequestIdsOf:profile];
  XCTAssertNotEqualObjects(ids[0], ids[1], @"two sends shared a request_id");
}

@end
