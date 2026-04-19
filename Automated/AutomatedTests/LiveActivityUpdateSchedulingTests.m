#import <XCTest/XCTest.h>

#import "TeakOperation.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Re-expose internal replyParser property for testing
@interface TeakOperation ()
@property (nonatomic, copy, nullable) id (^replyParser)(NSDictionary* _Nonnull);
@end

@interface LiveActivityUpdateSchedulingTests : XCTestCase
@end

@implementation LiveActivityUpdateSchedulingTests

#pragma mark - Helpers

- (NSTimeInterval)sampleOffset {
  // 1 hour — well inside the 10-hour server horizon, far from the ≤ 0 validation edge.
  return 3600;
}

- (NSDictionary*)sampleCustomData {
  return @{@"score" : @42, @"period" : @2};
}

- (NSDictionary*)sampleSystemData {
  return @{@"event" : @"update", @"stale-date" : @1760003600};
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
  return [Teak scheduleLiveActivityUpdate:@"chest_timer"
                                   offset:[self sampleOffset]
                               customData:[self sampleCustomData]
                               systemData:[self sampleSystemData]];
}

#pragma mark - Input validation: activityId

- (void)testNilActivityIdReturnsErrorOperation {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
  TeakOperation* op = [Teak scheduleLiveActivityUpdate:nil
                                                offset:[self sampleOffset]
                                            customData:[self sampleCustomData]
                                            systemData:[self sampleSystemData]];
#pragma clang diagnostic pop

  XCTAssertNotNil(op);

  TeakOperationResult* result = [self runOperationAndGetResult:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"activityId"]);
}

- (void)testEmptyActivityIdReturnsErrorOperation {
  TeakOperation* op = [Teak scheduleLiveActivityUpdate:@""
                                                offset:[self sampleOffset]
                                            customData:[self sampleCustomData]
                                            systemData:[self sampleSystemData]];

  XCTAssertNotNil(op);

  TeakOperationResult* result = [self runOperationAndGetResult:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"activityId"]);
}

#pragma mark - Input validation: offset

- (void)testZeroOffsetReturnsErrorOperation {
  TeakOperation* op = [Teak scheduleLiveActivityUpdate:@"chest_timer"
                                                offset:0
                                            customData:[self sampleCustomData]
                                            systemData:[self sampleSystemData]];

  XCTAssertNotNil(op);

  TeakOperationResult* result = [self runOperationAndGetResult:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"offset"]);
}

- (void)testNegativeOffsetReturnsErrorOperation {
  TeakOperation* op = [Teak scheduleLiveActivityUpdate:@"chest_timer"
                                                offset:-60
                                            customData:[self sampleCustomData]
                                            systemData:[self sampleSystemData]];

  XCTAssertNotNil(op);

  TeakOperationResult* result = [self runOperationAndGetResult:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"offset"]);
}

#pragma mark - Input validation: customData

- (void)testNilCustomDataReturnsErrorOperation {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
  TeakOperation* op = [Teak scheduleLiveActivityUpdate:@"chest_timer"
                                                offset:[self sampleOffset]
                                            customData:nil
                                            systemData:[self sampleSystemData]];
#pragma clang diagnostic pop

  XCTAssertNotNil(op);

  TeakOperationResult* result = [self runOperationAndGetResult:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"customData"]);
}

- (void)testEmptyCustomDataIsAllowed {
  // Server-side only requires custom_data be non-nil; an empty content-state dict is a valid
  // (if unusual) payload. Asserting explicitly so a future "tighten validation" change
  // doesn't silently break callers that rely on this.
  TeakOperation* op = [Teak scheduleLiveActivityUpdate:@"chest_timer"
                                                offset:[self sampleOffset]
                                            customData:@{}
                                            systemData:[self sampleSystemData]];

  NSDictionary* payload = [self requestParamsFromOperation:op][@"payload"];
  XCTAssertEqualObjects(payload[@"custom_data"], @"{}",
                        @"empty customData should serialize to \"{}\", not short-circuit to an error");
}

- (void)testNonSerializableCustomDataReturnsErrorOperation {
  // NSDate is not a valid JSON leaf; NSJSONSerialization will reject it.
  NSDictionary* badData = @{@"when" : [NSDate date]};
  TeakOperation* op = [Teak scheduleLiveActivityUpdate:@"chest_timer"
                                                offset:[self sampleOffset]
                                            customData:badData
                                            systemData:[self sampleSystemData]];

  XCTAssertNotNil(op);

  TeakOperationResult* result = [self runOperationAndGetResult:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"customData"]);
}

#pragma mark - Input validation: systemData

- (void)testNilSystemDataIsAllowed {
  TeakOperation* op = [Teak scheduleLiveActivityUpdate:@"chest_timer"
                                                offset:[self sampleOffset]
                                            customData:[self sampleCustomData]
                                            systemData:nil];

  XCTAssertNotNil(op);
  // nil systemData should build a real request operation (not an error short-circuit).
  NSDictionary* payload = [self requestParamsFromOperation:op][@"payload"];
  XCTAssertNotNil(payload, @"nil systemData should produce a real request operation");
}

- (void)testNonSerializableSystemDataReturnsErrorOperation {
  NSDictionary* badData = @{@"when" : [NSDate date]};
  TeakOperation* op = [Teak scheduleLiveActivityUpdate:@"chest_timer"
                                                offset:[self sampleOffset]
                                            customData:[self sampleCustomData]
                                            systemData:badData];

  XCTAssertNotNil(op);

  TeakOperationResult* result = [self runOperationAndGetResult:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"systemData"]);
}

#pragma mark - Request construction

- (void)testRequestUsesCorrectEndpoint {
  TeakOperation* op = [self validOperation];

  NSDictionary* requestParams = [self requestParamsFromOperation:op];
  XCTAssertEqualObjects(requestParams[@"endpoint"], @"/me/live_activity_updates");
}

- (void)testRequestPayloadContainsActivityId {
  TeakOperation* op = [self validOperation];

  NSDictionary* payload = [self requestParamsFromOperation:op][@"payload"];
  XCTAssertEqualObjects(payload[@"live_activity_id"], @"chest_timer");
}

- (void)testRequestPayloadContainsOffsetSecondsAsInteger {
  TeakOperation* op = [self validOperation];

  NSDictionary* payload = [self requestParamsFromOperation:op][@"payload"];
  XCTAssertEqualObjects(payload[@"offset_seconds"], @3600,
                        @"offset_seconds should be an integer NSNumber (truncated from NSTimeInterval)");
}

- (void)testFractionalOffsetIsTruncatedToInteger {
  TeakOperation* op = [Teak scheduleLiveActivityUpdate:@"chest_timer"
                                                offset:7.9
                                            customData:[self sampleCustomData]
                                            systemData:[self sampleSystemData]];

  NSDictionary* payload = [self requestParamsFromOperation:op][@"payload"];
  XCTAssertEqualObjects(payload[@"offset_seconds"], @7,
                        @"offset_seconds should truncate (not round) sub-second precision");
}

- (void)testRequestPayloadContainsCustomDataAsJSONString {
  TeakOperation* op = [self validOperation];

  NSDictionary* payload = [self requestParamsFromOperation:op][@"payload"];
  id customData = payload[@"custom_data"];
  XCTAssertTrue([customData isKindOfClass:[NSString class]],
                @"custom_data must be sent as a JSON string, not an NSDictionary");

  NSData* data = [(NSString*)customData dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary* roundTrip = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  XCTAssertEqualObjects(roundTrip, [self sampleCustomData]);
}

- (void)testRequestPayloadContainsSystemDataAsJSONString {
  TeakOperation* op = [self validOperation];

  NSDictionary* payload = [self requestParamsFromOperation:op][@"payload"];
  id systemData = payload[@"system_data"];
  XCTAssertTrue([systemData isKindOfClass:[NSString class]]);

  NSData* data = [(NSString*)systemData dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary* roundTrip = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  XCTAssertEqualObjects(roundTrip, [self sampleSystemData]);
}

- (void)testNilSystemDataIsAbsentOrNullInPayload {
  TeakOperation* op = [Teak scheduleLiveActivityUpdate:@"chest_timer"
                                                offset:[self sampleOffset]
                                            customData:[self sampleCustomData]
                                            systemData:nil];

  NSDictionary* payload = [self requestParamsFromOperation:op][@"payload"];
  id systemData = payload[@"system_data"];
  // Either absent or NSNull is acceptable — both map to nil server-side.
  XCTAssertTrue(systemData == nil || systemData == [NSNull null],
                @"Expected nil systemData to be absent or NSNull in payload, got %@", systemData);
}

#pragma mark - Reply parser

- (void)testReplyParserReturnsSuccessForOkStatus {
  TeakOperation* op = [self validOperation];

  NSDictionary* reply = @{@"status" : @"ok", @"event" : @{@"id" : @12345}};
  TeakOperationResult* result = op.replyParser(reply);

  XCTAssertFalse(result.error);
  XCTAssertEqualObjects(result.status, @"ok");
}

- (void)testReplyParserReturnsErrorForErrorStatus {
  TeakOperation* op = [self validOperation];

  NSDictionary* reply = @{@"status" : @"error", @"errors" : @{@"offset_seconds" : @[ @"outside window" ]}};
  TeakOperationResult* result = op.replyParser(reply);

  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"offset_seconds"]);
}

- (void)testReplyParserReturnsErrorForInvalidDevice {
  TeakOperation* op = [self validOperation];

  NSDictionary* reply = @{@"status" : @"invalid_device", @"device_id" : @"nonexistent"};
  TeakOperationResult* result = op.replyParser(reply);

  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"invalid_device");
}

@end
