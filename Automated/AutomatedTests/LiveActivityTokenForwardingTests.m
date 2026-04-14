#import <XCTest/XCTest.h>

#import "TeakOperation.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

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

#pragma mark - Input validation: activityId

- (void)testNilActivityIdReturnsErrorOperation {
  NSData* token = [self sampleTokenData];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
  TeakOperation* op = [Teak startedLiveActivity:nil withToken:token];
#pragma clang diagnostic pop

  XCTAssertNotNil(op, @"Should return an operation even for nil activityId");

  TeakOperationResult* result = [self runOperationAndGetResult:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error, @"Result should be an error");
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"activityId"]);
}

- (void)testEmptyActivityIdReturnsErrorOperation {
  NSData* token = [self sampleTokenData];
  TeakOperation* op = [Teak startedLiveActivity:@"" withToken:token];

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
  TeakOperation* op = [Teak startedLiveActivity:@"my-activity" withToken:nil];
#pragma clang diagnostic pop

  XCTAssertNotNil(op, @"Should return an operation even for nil token");

  TeakOperationResult* result = [self runOperationAndGetResult:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error, @"Result should be an error");
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"token"]);
}

- (void)testEmptyTokenReturnsErrorOperation {
  TeakOperation* op = [Teak startedLiveActivity:@"my-activity" withToken:[NSData data]];

  XCTAssertNotNil(op, @"Should return an operation even for empty token");

  TeakOperationResult* result = [self runOperationAndGetResult:op];
  XCTAssertNotNil(result);
  XCTAssertTrue(result.error, @"Result should be an error");
  XCTAssertEqualObjects(result.status, @"error");
  XCTAssertNotNil(result.errors[@"token"]);
}

#pragma mark - Valid inputs

- (void)testValidInputsReturnsNonNilOperation {
  TeakOperation* op = [Teak startedLiveActivity:@"my-activity" withToken:[self sampleTokenData]];

  XCTAssertNotNil(op, @"Should return a TeakOperation for valid inputs");
}

@end
