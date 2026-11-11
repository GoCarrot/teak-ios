#import <XCTest/XCTest.h>

#import "TeakConfiguration.h"
#import "TeakLiveActivityTokenCache.h"
#import "TeakOperationTestDriver.h"
#import "TeakSession.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

extern TeakSession* currentSession;
extern Teak* _teakSharedInstance;

@interface Teak (LiveActivityTokenForwardingTests)
@property (strong, nonatomic) NSOperationQueue* _Nonnull operationQueue;
@end

@interface TeakSession (LiveActivityTokenForwardingTests)
+ (void)logoutReusingCurrentSession:(BOOL)reuseSession;
- (void)detachDeviceConfigurationObservers;
@end

@interface LiveActivityTokenForwardingTests : XCTestCase
@property (nonatomic) TeakOperationTestDriver* driver;
@property (nonatomic) Teak* savedSharedInstance;
@end

@implementation LiveActivityTokenForwardingTests

// The user-change test drives a real session, which reads TeakConfiguration.
+ (void)setUp {
  [super setUp];
  @try {
    [TeakConfiguration configureForAppId:@"test-app" andSecret:@"test-secret"];
  } @catch (NSException* exception) {
    // Already initialized by another test.
  }
}

- (void)setUp {
  [super setUp];
  self.driver = [[TeakOperationTestDriver alloc] init];
  self.savedSharedInstance = _teakSharedInstance;
  // Running an operation that unexpectedly turned into a real request would block forever.
  self.continueAfterFailure = NO;
  // The cache is process-wide and most tests here forward the same activity and token.
  [[TeakLiveActivityTokenCache sharedCache] reset];
}

- (void)tearDown {
  // A real session stays a live deviceConfiguration KVO observer until detached.
  [currentSession detachDeviceConfigurationObservers];
  currentSession = nil;
  _teakSharedInstance = self.savedSharedInstance;
  [super tearDown];
}

#pragma mark - Helpers

- (NSData*)sampleTokenData {
  unsigned char bytes[] = {0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0x01, 0x23};
  return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}

- (TeakOperation*)validOperation {
  return [Teak startedLiveActivity:@"my-activity"
                         withToken:[self sampleTokenData]
                  systemActivityId:@"system-activity-uuid"];
}

- (TeakOperation*)operationWithToken:(NSData*)token {
  return [Teak startedLiveActivity:@"my-activity" withToken:token systemActivityId:@"system-activity-uuid"];
}

- (NSData*)otherTokenData {
  unsigned char bytes[] = {0x01, 0x02, 0x03, 0x04};
  return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}

// A request-backed operation carries {endpoint, payload}; a validation failure just carries its result.
- (BOOL)sendsRequest:(TeakOperation*)op {
  return op.invocation.selector == NSSelectorFromString(@"performRequest:");
}

#pragma mark - Input validation: activityId

- (void)testNilActivityIdReturnsErrorOperation {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
  TeakOperation* op = [Teak startedLiveActivity:nil
                                      withToken:[self sampleTokenData]
                               systemActivityId:@"system-activity-uuid"];
#pragma clang diagnostic pop

  XCTAssertNotNil(op, @"Should return an operation even for nil activityId");

  TeakOperationResult* result = [self.driver runSync:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error, @"Result should be an error");
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"activityId"]);
}

- (void)testEmptyActivityIdReturnsErrorOperation {
  TeakOperation* op = [Teak startedLiveActivity:@""
                                      withToken:[self sampleTokenData]
                               systemActivityId:@"system-activity-uuid"];

  XCTAssertNotNil(op, @"Should return an operation even for empty activityId");

  TeakOperationResult* result = [self.driver runSync:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error, @"Result should be an error");
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"activityId"]);
}

#pragma mark - Input validation: token

- (void)testNilTokenReturnsErrorOperation {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
  TeakOperation* op = [Teak startedLiveActivity:@"my-activity"
                                      withToken:nil
                               systemActivityId:@"system-activity-uuid"];
#pragma clang diagnostic pop

  XCTAssertNotNil(op, @"Should return an operation even for nil token");

  TeakOperationResult* result = [self.driver runSync:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error, @"Result should be an error");
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"token"]);
}

- (void)testEmptyTokenReturnsErrorOperation {
  TeakOperation* op = [Teak startedLiveActivity:@"my-activity"
                                      withToken:[NSData data]
                               systemActivityId:@"system-activity-uuid"];

  XCTAssertNotNil(op, @"Should return an operation even for empty token");

  TeakOperationResult* result = [self.driver runSync:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error, @"Result should be an error");
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"token"]);
}

#pragma mark - Input validation: systemActivityId

- (void)testNilSystemActivityIdReturnsErrorOperation {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
  TeakOperation* op = [Teak startedLiveActivity:@"my-activity"
                                      withToken:[self sampleTokenData]
                               systemActivityId:nil];
#pragma clang diagnostic pop

  XCTAssertNotNil(op, @"Should return an operation even for nil systemActivityId");

  TeakOperationResult* result = [self.driver runSync:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error, @"Result should be an error");
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"systemActivityId"]);
}

- (void)testEmptySystemActivityIdReturnsErrorOperation {
  TeakOperation* op = [Teak startedLiveActivity:@"my-activity"
                                      withToken:[self sampleTokenData]
                               systemActivityId:@""];

  XCTAssertNotNil(op, @"Should return an operation even for empty systemActivityId");

  TeakOperationResult* result = [self.driver runSync:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error, @"Result should be an error");
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"systemActivityId"]);
}

#pragma mark - Request construction

- (void)testRequestUsesCorrectEndpoint {
  TeakOperation* op = [self validOperation];

  NSDictionary* requestParams = [self.driver requestParamsFor:op];
  XCTAssertEqualObjects(requestParams[@"endpoint"], @"/me/live_activities");
}

- (void)testRequestPayloadContainsActivityId {
  TeakOperation* op = [self validOperation];

  NSDictionary* payload = [self.driver requestParamsFor:op][@"payload"];
  XCTAssertEqualObjects(payload[@"live_activity_id"], @"my-activity",
                        @"Payload should contain the activity ID as live_activity_id");
}

- (void)testRequestPayloadContainsHexEncodedToken {
  TeakOperation* op = [self validOperation];

  NSDictionary* payload = [self.driver requestParamsFor:op][@"payload"];
  XCTAssertEqualObjects(payload[@"token"], @"deadbeefcafe0123",
                        @"Payload should contain the token as a lowercase hex string");
}

- (void)testRequestPayloadContainsSystemActivityId {
  TeakOperation* op = [self validOperation];

  NSDictionary* payload = [self.driver requestParamsFor:op][@"payload"];
  XCTAssertEqualObjects(payload[@"system_activity_id"], @"system-activity-uuid",
                        @"Payload should contain the systemActivityId as system_activity_id");
}

#pragma mark - Reply parser

- (void)testReplyParserReturnsSuccessForOkStatus {
  TeakOperation* op = [self validOperation];

  NSDictionary* reply = @{@"status" : @"ok"};
  TeakOperationResult* result = op.replyParser(reply);

  XCTAssertFalse(result.error);
  XCTAssertEqualObjects(result.status, @"ok");
}

- (void)testReplyParserReturnsErrorForInvalidDevice {
  TeakOperation* op = [self validOperation];

  NSDictionary* reply = @{@"status" : @"invalid_device", @"errors" : @{@"device_id" : @[ @"not found" ]}};
  TeakOperationResult* result = op.replyParser(reply);

  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"invalid_device");
  XCTAssertNotNil(result.errors[@"device_id"]);
}

#pragma mark - Dedupe

// Dedupe only records when there is a queue to send on. The queue is suspended so nothing runs, and
// the operations are inspected rather than run.
- (void)installSharedInstance {
  Teak* teak = [[Teak alloc] init];
  teak.operationQueue = [[NSOperationQueue alloc] init];
  teak.operationQueue.suspended = YES;
  _teakSharedInstance = teak;
}

- (void)testNoSharedInstanceMeansNothingIsRecorded {
  _teakSharedInstance = nil;
  TeakOperation* first = [self validOperation];
  XCTAssertTrue([self sendsRequest:first]);
  TeakOperation* second = [self validOperation];
  XCTAssertNotEqual(second, first, @"Without a queue nothing was sent, so the next emission must not reuse the first");
  XCTAssertTrue([self sendsRequest:second]);
}

- (void)testRepeatedTokenReturnsTheOperationAlreadySent {
  [self installSharedInstance];
  TeakOperation* first = [self validOperation];
  XCTAssertTrue([self sendsRequest:first]);

  TeakOperation* repeat = [self validOperation];
  XCTAssertEqual(repeat, first, @"Same activity, token and system id should share the original operation");
}

- (void)testRepeatedTokenSharesTheFailureOfTheOriginalSend {
  [self installSharedInstance];
  TeakOperation* first = [self validOperation];
  TeakOperation* repeat = [self validOperation];
  XCTAssertEqual(repeat, first);

  TeakOperationResult* result = first.replyParser(@{@"status" : @"invalid_device", @"errors" : @{@"device_id" : @[ @"not found" ]}});
  XCTAssertTrue(result.error, @"The repeat's caller holds the operation that failed");

  TeakOperation* retry = [self validOperation];
  XCTAssertNotEqual(retry, first);
  XCTAssertTrue([self sendsRequest:retry], @"A failed send must not block the next emission");
}

- (void)testCancelledOperationDoesNotBlockTheNextEmission {
  [self installSharedInstance];
  TeakOperation* first = [self validOperation];
  [first cancel];

  TeakOperation* next = [self validOperation];
  XCTAssertNotEqual(next, first);
  XCTAssertTrue([self sendsRequest:next]);
}

- (void)testChangedTokenIsForwarded {
  [self installSharedInstance];
  TeakOperation* first = [self validOperation];
  TeakOperation* changed = [self operationWithToken:[self otherTokenData]];
  XCTAssertNotEqual(changed, first);
  XCTAssertTrue([self sendsRequest:changed]);
}

- (void)testChangedSystemActivityIdIsForwarded {
  [self installSharedInstance];
  TeakOperation* first = [self validOperation];
  TeakOperation* op = [Teak startedLiveActivity:@"my-activity" withToken:[self sampleTokenData] systemActivityId:@"other-system-activity-uuid"];
  XCTAssertNotEqual(op, first);
  XCTAssertTrue([self sendsRequest:op]);
}

- (void)testChangedActivityIdIsForwarded {
  [self installSharedInstance];
  TeakOperation* first = [self validOperation];
  TeakOperation* op = [Teak startedLiveActivity:@"other-activity" withToken:[self sampleTokenData] systemActivityId:@"system-activity-uuid"];
  XCTAssertNotEqual(op, first);
  XCTAssertTrue([self sendsRequest:op]);
}

- (void)testSuccessfulReplyKeepsTheTokenDeduped {
  [self installSharedInstance];
  TeakOperation* first = [self validOperation];
  first.replyParser(@{@"status" : @"ok"});

  XCTAssertEqual([self validOperation], first);
}

- (void)testInvalidArgumentsAreNotRecorded {
  [self installSharedInstance];
  TeakOperation* bad = [Teak startedLiveActivity:@"my-activity" withToken:[self sampleTokenData] systemActivityId:@""];
  XCTAssertFalse([self sendsRequest:bad]);

  XCTAssertTrue([self sendsRequest:[self validOperation]]);
}

- (void)testUserChangeLetsTheSameTokenBeForwardedAgain {
  [self installSharedInstance];
  TeakOperation* first = [self validOperation];
  XCTAssertTrue([self sendsRequest:first]);
  XCTAssertEqual([self validOperation], first);

  [TeakSession logoutReusingCurrentSession:NO];

  TeakOperation* afterUserChange = [self validOperation];
  XCTAssertNotEqual(afterUserChange, first);
  XCTAssertTrue([self sendsRequest:afterUserChange]);
}

@end
