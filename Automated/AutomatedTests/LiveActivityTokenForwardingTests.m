#import <XCTest/XCTest.h>

#import "TeakOperation.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Re-expose internal replyParser property for testing
@interface TeakOperation ()
@property (nonatomic, copy, nullable) id (^replyParser)(NSDictionary* _Nonnull);
@end

@interface LiveActivityTokenForwardingTests : XCTestCase
@end

@implementation LiveActivityTokenForwardingTests

#pragma mark - Helpers

- (NSData*)sampleTokenData {
  unsigned char bytes[] = {0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0x01, 0x23};
  return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}

- (TeakOperationResult*)runOperationAndGetResult:(TeakOperation*)op {
  NSOperationQueue* queue = [[NSOperationQueue alloc] init];
  [queue addOperation:op];
  [queue waitUntilAllOperationsAreFinished];
  return (TeakOperationResult*)[op result];
}

/// Extract the request params dictionary (endpoint + payload) from a TeakOperation's invocation.
- (NSDictionary*)requestParamsFromOperation:(TeakOperation*)op {
  NSInvocation* inv = op.invocation;
  __unsafe_unretained NSDictionary* requestParams;
  [inv getArgument:&requestParams atIndex:2];
  return requestParams;
}

- (TeakOperation*)validOperation {
  return [Teak startedLiveActivity:@"my-activity"
                         withToken:[self sampleTokenData]
                  systemActivityId:@"system-activity-uuid"];
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

  TeakOperationResult* result = [self runOperationAndGetResult:op];
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

  TeakOperationResult* result = [self runOperationAndGetResult:op];
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

  TeakOperationResult* result = [self runOperationAndGetResult:op];
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

  TeakOperationResult* result = [self runOperationAndGetResult:op];
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

  TeakOperationResult* result = [self runOperationAndGetResult:op];
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

  TeakOperationResult* result = [self runOperationAndGetResult:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error, @"Result should be an error");
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"systemActivityId"]);
}

#pragma mark - Request construction

- (void)testRequestUsesCorrectEndpoint {
  TeakOperation* op = [self validOperation];

  NSDictionary* requestParams = [self requestParamsFromOperation:op];
  XCTAssertEqualObjects(requestParams[@"endpoint"], @"/me/live_activities");
}

- (void)testRequestPayloadContainsActivityId {
  TeakOperation* op = [self validOperation];

  NSDictionary* payload = [self requestParamsFromOperation:op][@"payload"];
  XCTAssertEqualObjects(payload[@"live_activity_id"], @"my-activity",
                        @"Payload should contain the activity ID as live_activity_id");
}

- (void)testRequestPayloadContainsHexEncodedToken {
  TeakOperation* op = [self validOperation];

  NSDictionary* payload = [self requestParamsFromOperation:op][@"payload"];
  XCTAssertEqualObjects(payload[@"token"], @"deadbeefcafe0123",
                        @"Payload should contain the token as a lowercase hex string");
}

- (void)testRequestPayloadContainsSystemActivityId {
  TeakOperation* op = [self validOperation];

  NSDictionary* payload = [self requestParamsFromOperation:op][@"payload"];
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

@end
