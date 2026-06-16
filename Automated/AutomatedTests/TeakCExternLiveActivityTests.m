#import <XCTest/XCTest.h>

#import "PushRegistrationEvent.h"
#import "TeakEvent.h"
#import "TeakOperationTestDriver.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Expose the internal serial event processing queue so tests can flush pending events.
@interface TeakEvent (PushToStartTesting)
+ (dispatch_queue_t)eventProcessingQueue;
@end

// Forward declarations for the TeakCExtern Live Activity wrappers. They are
// defined in TeakCExtern.m (compiled into Teak.framework) and consumed from
// Unity via the same extern pattern.
extern TeakOperation* TeakStartedLiveActivity(const char* activityId,
                                              const void* pushTokenBytes,
                                              int pushTokenLength,
                                              const char* systemActivityId);
extern TeakOperation* TeakScheduleLiveActivityUpdate(const char* activityId,
                                                    int64_t offset,
                                                    const char* customDataJson,
                                                    const char* systemDataJson);
extern TeakOperation* TeakCancelLiveActivityUpdates(const char* activityId);
extern void TeakRegisterPushToStartToken(const void* pushTokenBytes, int pushTokenLength);

@interface TeakCExternLiveActivityTests : XCTestCase
@property (nonatomic) TeakOperationTestDriver* driver;
@end

@implementation TeakCExternLiveActivityTests

- (void)setUp {
  [super setUp];
  self.driver = [[TeakOperationTestDriver alloc] init];
}

#pragma mark - TeakStartedLiveActivity

- (void)testStartedLiveActivity_BuildsValidRequest {
  unsigned char bytes[] = {0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0x01, 0x23};
  TeakOperation* op = TeakStartedLiveActivity("chest_timer", bytes, (int)sizeof(bytes), "system-activity-uuid");

  XCTAssertNotNil(op);

  NSDictionary* requestParams = [self.driver requestParamsFor:op];
  XCTAssertEqualObjects(requestParams[@"endpoint"], @"/me/live_activities");

  NSDictionary* payload = requestParams[@"payload"];
  XCTAssertEqualObjects(payload[@"live_activity_id"], @"chest_timer");
  XCTAssertEqualObjects(payload[@"system_activity_id"], @"system-activity-uuid");
  XCTAssertEqualObjects(payload[@"token"], @"deadbeefcafe0123",
                        @"Token bytes should be marshalled to a lowercase hex string");
}

- (void)testStartedLiveActivity_NullPushTokenSurfacesErrorResult {
  TeakOperation* op = TeakStartedLiveActivity("chest_timer", NULL, 0, "system-activity-uuid");

  XCTAssertNotNil(op, @"Wrapper should still return an operation for a NULL token");

  TeakOperationResult* result = [self.driver runSync:op];
  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"token"]);
}

- (void)testStartedLiveActivity_NullActivityIdSurfacesErrorResult {
  unsigned char bytes[] = {0xde, 0xad, 0xbe, 0xef};
  TeakOperation* op = TeakStartedLiveActivity(NULL, bytes, (int)sizeof(bytes), "system-activity-uuid");

  XCTAssertNotNil(op, @"Wrapper should still return an operation for a NULL activityId");

  TeakOperationResult* result = [self.driver runSync:op];
  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"activityId"]);
}

#pragma mark - TeakScheduleLiveActivityUpdate

- (void)testScheduleLiveActivityUpdate_BuildsValidRequest {
  TeakOperation* op = TeakScheduleLiveActivityUpdate("chest_timer",
                                                     3600,
                                                     "{\"score\":42,\"period\":2}",
                                                     "{\"event\":\"update\"}");

  XCTAssertNotNil(op);

  NSDictionary* requestParams = [self.driver requestParamsFor:op];
  XCTAssertEqualObjects(requestParams[@"endpoint"], @"/me/live_activity_updates");

  NSDictionary* payload = requestParams[@"payload"];
  XCTAssertEqualObjects(payload[@"live_activity_id"], @"chest_timer");
  XCTAssertEqualObjects(payload[@"offset_seconds"], @3600);

  NSData* customBytes = [payload[@"custom_data"] dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary* customRoundTrip = [NSJSONSerialization JSONObjectWithData:customBytes options:0 error:nil];
  XCTAssertEqualObjects(customRoundTrip, (@{@"score" : @42, @"period" : @2}));

  NSData* systemBytes = [payload[@"system_data"] dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary* systemRoundTrip = [NSJSONSerialization JSONObjectWithData:systemBytes options:0 error:nil];
  XCTAssertEqualObjects(systemRoundTrip, (@{@"event" : @"update"}));
}

- (void)testScheduleLiveActivityUpdate_NullSystemDataJsonIsAllowed {
  TeakOperation* op = TeakScheduleLiveActivityUpdate("chest_timer",
                                                     3600,
                                                     "{\"score\":42}",
                                                     NULL);

  XCTAssertNotNil(op);

  NSDictionary* payload = [self.driver requestParamsFor:op][@"payload"];
  XCTAssertEqualObjects(payload[@"system_data"], [NSNull null],
                        @"NULL systemDataJson should serialize to NSNull on the payload");
}

- (void)testScheduleLiveActivityUpdate_NullActivityIdSurfacesErrorResult {
  TeakOperation* op = TeakScheduleLiveActivityUpdate(NULL,
                                                     3600,
                                                     "{\"score\":42}",
                                                     "{\"event\":\"update\"}");

  XCTAssertNotNil(op, @"Wrapper should still return an operation for a NULL activityId");

  TeakOperationResult* result = [self.driver runSync:op];
  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"activityId"]);
}

- (void)testScheduleLiveActivityUpdate_MalformedCustomDataJsonSurfacesError {
  // Must not crash. Malformed JSON parses to nil; the underlying ObjC method
  // then rejects nil customData with a status=error, errors[customData] result.
  TeakOperation* op = TeakScheduleLiveActivityUpdate("chest_timer",
                                                     3600,
                                                     "not{valid}json",
                                                     "{\"event\":\"update\"}");

  XCTAssertNotNil(op);

  TeakOperationResult* result = [self.driver runSync:op];
  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"customData"]);
}

- (void)testScheduleLiveActivityUpdate_MalformedSystemDataJsonDoesNotCrash {
  // Malformed systemDataJson parses to nil, which is a valid (absent) systemData
  // per the underlying ObjC API — so the operation should still build a real
  // request rather than error out.
  TeakOperation* op = TeakScheduleLiveActivityUpdate("chest_timer",
                                                     3600,
                                                     "{\"score\":42}",
                                                     "not{valid}json");

  XCTAssertNotNil(op);

  NSDictionary* payload = [self.driver requestParamsFor:op][@"payload"];
  XCTAssertNotNil(payload, @"Malformed systemDataJson should not short-circuit to an error");
  XCTAssertEqualObjects(payload[@"system_data"], [NSNull null],
                        @"Malformed systemDataJson should be treated as absent (NSNull on payload)");
}

#pragma mark - TeakCancelLiveActivityUpdates

- (void)testCancelLiveActivityUpdates_BuildsValidRequest {
  TeakOperation* op = TeakCancelLiveActivityUpdates("chest_timer");

  XCTAssertNotNil(op);

  NSDictionary* requestParams = [self.driver requestParamsFor:op];
  XCTAssertEqualObjects(requestParams[@"endpoint"], @"/me/cancel_all_live_activity_updates");

  NSDictionary* payload = requestParams[@"payload"];
  XCTAssertEqualObjects(payload[@"live_activity_id"], @"chest_timer");
}

- (void)testCancelLiveActivityUpdates_NullActivityIdSurfacesErrorResult {
  TeakOperation* op = TeakCancelLiveActivityUpdates(NULL);

  XCTAssertNotNil(op, @"Wrapper should still return an operation for a NULL activityId");

  TeakOperationResult* result = [self.driver runSync:op];
  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"activityId"]);
}

@end

#pragma mark - TeakCExternPushToStartTokenTests

@interface TeakCExternPushToStartTokenTests : XCTestCase
@property (strong, nonatomic) NSMutableArray<PushRegistrationEvent*>* capturedEvents;
@property (strong, nonatomic) TeakEventBlockHandler* handler;
@end

@implementation TeakCExternPushToStartTokenTests

- (void)setUp {
  self.capturedEvents = [[NSMutableArray alloc] init];
  NSMutableArray* events = self.capturedEvents;
  self.handler = [TeakEventBlockHandler handlerWithBlock:^(TeakEvent* event) {
    if (event.type == LiveActivityPushToStartRegistered) {
      @synchronized(events) {
        [events addObject:(PushRegistrationEvent*)event];
      }
    }
  }];
  [TeakEvent addEventHandler:self.handler];
}

- (void)tearDown {
  [TeakEvent removeEventHandler:self.handler];
  self.handler = nil;
  self.capturedEvents = nil;
}

- (NSArray<PushRegistrationEvent*>*)drainCapturedEvents {
  dispatch_sync([TeakEvent eventProcessingQueue], ^{});
  @synchronized(self.capturedEvents) {
    return [self.capturedEvents copy];
  }
}

- (void)testRegisterPushToStartToken_ValidBytesPostEventWithHexToken {
  unsigned char bytes[] = {0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0x01, 0x23};
  TeakRegisterPushToStartToken(bytes, (int)sizeof(bytes));

  NSArray<PushRegistrationEvent*>* events = [self drainCapturedEvents];
  assertThat(events, hasCountOf(1));
  assertThat(events[0].token, is(@"deadbeefcafe0123"));
}

- (void)testRegisterPushToStartToken_NullBytesDoesNotPostEvent {
  TeakRegisterPushToStartToken(NULL, 0);
  assertThat([self drainCapturedEvents], hasCountOf(0));
}

- (void)testRegisterPushToStartToken_ZeroLengthDoesNotPostEvent {
  unsigned char bytes[] = {0xde, 0xad};
  TeakRegisterPushToStartToken(bytes, 0);
  assertThat([self drainCapturedEvents], hasCountOf(0));
}

@end
