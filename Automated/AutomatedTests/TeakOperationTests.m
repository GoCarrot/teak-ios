#import <XCTest/XCTest.h>

#import <Teak/Teak.h>

#import "TeakOperationTestDriver.h"

// A TeakOperation must deallocate once nothing outside it holds a reference: an
// operation that owns a strong path back to itself never frees, and every call that
// returns one leaks it.
@interface TeakOperationTests : XCTestCase
@property (strong, nonatomic) TeakOperationTestDriver* driver;
@end

@implementation TeakOperationTests

- (void)setUp {
  [super setUp];
  self.driver = [[TeakOperationTestDriver alloc] init];
}

// Builds an operation inside its own autorelease pool, optionally runs it, and
// returns only a weak reference so the caller can check it freed.
- (void)assertOperationDeallocates:(TeakOperation* (^)(void))make run:(BOOL)run {
  __weak TeakOperation* weakOp = nil;
  @autoreleasepool {
    TeakOperation* op = make();
    XCTAssertNotNil(op);
    if (run) {
      [self.driver runSync:op];
      XCTAssertTrue(op.isFinished);
    }
    weakOp = op;
  }
  XCTAssertNil(weakOp, @"TeakOperation was never deallocated");
}

- (void)testWithResultDeallocates {
  TeakOperationResult* (^result)(void) = ^{ return [[TeakOperationResult alloc] initWithStatus:@"ok" andErrors:nil]; };
  [self assertOperationDeallocates:^{ return [TeakOperation withResult:result()]; } run:YES];
  [self assertOperationDeallocates:^{ return [TeakOperation withResult:result()]; } run:NO];
}

// Not run: running an endpoint operation waits on a live session.
- (void)testForEndpointDeallocates {
  [self assertOperationDeallocates:^{
    return [TeakOperation forEndpoint:@"/me/test"
                          withPayload:@{@"key" : @"value"}
                          replyParser:^id _Nullable(NSDictionary* _Nonnull reply) { return reply; }];
  }
                               run:NO];
}

@end
