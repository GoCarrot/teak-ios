#import <XCTest/XCTest.h>

#import "TeakOperationTestDriver.h"
#import "TeakSession.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Read by +[TeakSession whenUserIdIsOrWasReadyRun:]; set directly so a test can stand in an
// identified session without a real one.
extern TeakSession* currentSession;

// A TeakOperation must deallocate once nothing outside it holds a reference: an
// operation that owns a strong path back to itself never frees, and every call that
// returns one leaks it.
@interface TeakOperationTests : XCTestCase
@property (strong, nonatomic) TeakOperationTestDriver* driver;
@end

@implementation TeakOperationTests

- (void)tearDown {
  currentSession = nil;
  [super tearDown];
}

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
      [op start];
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

// Stands in for the work an operation's invocation runs, raising instead of returning.
- (id)returnResult:(id)result {
  [NSException raise:@"TeakOperationTestException" format:@"raised from the operation's work"];
  return nil;
}

- (void)testRaiseInWorkFinishesWithErrorResult {
  TeakOperation* op = [TeakOperation withResult:[[TeakOperationResult alloc] initWithStatus:@"ok" andErrors:nil]];
  op.invocation.target = self;

  TeakOperationResult* result = nil;
  XCTAssertNoThrow(result = [self.driver runSync:op]);
  XCTAssertTrue(op.isFinished);
  XCTAssertTrue([result isKindOfClass:[TeakOperationResult class]]);
  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"error");
}

- (void)testResultOfOperationCancelledBeforeRunIsErrorResult {
  TeakOperation* op = [TeakOperation withResult:[[TeakOperationResult alloc] initWithStatus:@"ok" andErrors:nil]];
  [op cancel];

  TeakOperationResult* result = nil;
  XCTAssertNoThrow(result = [self.driver runSync:op]);
  XCTAssertTrue([result isKindOfClass:[TeakOperationResult class]]);
  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.status, @"error");
}

// A session with no app configuration can't build a request, and a request that was never built
// never calls back; the operation must still finish.
- (void)testRequestThatCannotBeBuiltFinishesWithErrorResult {
  TeakSession* session = mock([TeakSession class]);
  [given([session currentState]) willReturn:[TeakSession UserIdentified]];
  currentSession = session;

  TeakOperation* op = [TeakOperation forEndpoint:@"/me/test" withPayload:@{@"key" : @"value"}];
  NSOperationQueue* queue = [[NSOperationQueue alloc] init];
  XCTestExpectation* finished = [[XCTKVOExpectation alloc] initWithKeyPath:@"isFinished" object:op expectedValue:@YES];
  [queue addOperation:op];
  [self waitForExpectations:@[ finished ] timeout:5.0];

  TeakOperationResult* result = (TeakOperationResult*)[op result];
  XCTAssertTrue([result isKindOfClass:[TeakOperationResult class]]);
  XCTAssertTrue(result.error);
}

- (void)testForEndpointWithPayloadKeepsPayload {
  TeakOperation* op = [TeakOperation forEndpoint:@"/me/test" withPayload:@{@"key" : @"value"}];
  NSDictionary* params = [self.driver requestParamsFor:op];
  XCTAssertEqualObjects(params[@"endpoint"], @"/me/test");
  XCTAssertEqualObjects(params[@"payload"], @{@"key" : @"value"});
}

@end
