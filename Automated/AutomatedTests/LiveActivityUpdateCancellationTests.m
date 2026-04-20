#import <XCTest/XCTest.h>

#import "TeakOperationTestDriver.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

@interface LiveActivityUpdateCancellationTests : XCTestCase
@property (nonatomic) TeakOperationTestDriver* driver;
@end

@implementation LiveActivityUpdateCancellationTests

- (void)setUp {
  [super setUp];
  self.driver = [[TeakOperationTestDriver alloc] init];
}

#pragma mark - Helpers

- (TeakOperation*)validOperation {
  return [Teak cancelLiveActivityUpdates:@"chest_timer"];
}

#pragma mark - Input validation

- (void)testNilActivityIdReturnsErrorOperation {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
  TeakOperation* op = [Teak cancelLiveActivityUpdates:nil];
#pragma clang diagnostic pop

  XCTAssertNotNil(op);

  TeakOperationResult* result = [self.driver runSync:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"activityId"]);
}

- (void)testEmptyActivityIdReturnsErrorOperation {
  TeakOperation* op = [Teak cancelLiveActivityUpdates:@""];

  XCTAssertNotNil(op);

  TeakOperationResult* result = [self.driver runSync:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"activityId"]);
}

#pragma mark - Request construction

- (void)testRequestUsesCorrectEndpoint {
  TeakOperation* op = [self validOperation];

  NSDictionary* requestParams = [self.driver requestParamsFor:op];
  XCTAssertEqualObjects(requestParams[@"endpoint"], @"/me/cancel_all_live_activity_updates");
}

- (void)testRequestPayloadContainsActivityId {
  TeakOperation* op = [self validOperation];

  NSDictionary* payload = [self.driver requestParamsFor:op][@"payload"];
  XCTAssertEqualObjects(payload[@"live_activity_id"], @"chest_timer");
}

#pragma mark - Reply parser

- (void)testReplyParserSurfacesCanceledCountForOk {
  TeakOperation* op = [self validOperation];

  NSDictionary* reply = @{@"status" : @"ok", @"canceled" : @3};
  TeakOperationLiveActivityCancelResult* result =
      (TeakOperationLiveActivityCancelResult*)op.replyParser(reply);

  XCTAssertFalse(result.error);
  XCTAssertEqualObjects(result.status, @"ok");
  XCTAssertTrue([result isKindOfClass:[TeakOperationLiveActivityCancelResult class]],
                @"Reply parser should return a TeakOperationLiveActivityCancelResult");
  XCTAssertEqual(result.canceled, 3);
}

- (void)testReplyParserZeroCanceledIsOk {
  TeakOperation* op = [self validOperation];

  NSDictionary* reply = @{@"status" : @"ok", @"canceled" : @0};
  TeakOperationLiveActivityCancelResult* result =
      (TeakOperationLiveActivityCancelResult*)op.replyParser(reply);

  XCTAssertFalse(result.error);
  XCTAssertEqual(result.canceled, 0);
}

- (void)testReplyParserReturnsErrorForInvalidDevice {
  TeakOperation* op = [self validOperation];

  NSDictionary* reply = @{@"status" : @"invalid_device", @"device_id" : @"nonexistent"};
  TeakOperationResult* result = op.replyParser(reply);

  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"invalid_device");
}

@end
