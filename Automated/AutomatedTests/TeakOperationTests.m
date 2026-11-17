#import <XCTest/XCTest.h>
#import <mach/mach.h>

#import "TeakOperationTestDriver.h"
#import "TeakSession.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Read by +[TeakSession whenUserIdIsOrWasReadyRun:]; set directly so a test can stand in an
// identified session without a real one.
extern TeakSession* currentSession;
extern NSString* const currentSessionMutex;

@interface TeakSession (TeakOperationTests)
+ (NSMutableArray*)whenUserIdIsReadyRunBlocks;
@end

static NSUInteger TeakTestThreadCount(void) {
  thread_act_array_t threads = NULL;
  mach_msg_type_number_t count = 0;
  if (task_threads(mach_task_self(), &threads, &count) != KERN_SUCCESS) {
    return 0;
  }
  for (mach_msg_type_number_t i = 0; i < count; i++) {
    mach_port_deallocate(mach_task_self(), threads[i]);
  }
  vm_deallocate(mach_task_self(), (vm_address_t)threads, count * sizeof(thread_act_t));
  return count;
}

@interface TeakOperationTests : XCTestCase
@property (strong, nonatomic) TeakOperationTestDriver* driver;
@end

@implementation TeakOperationTests

- (void)setUp {
  [super setUp];
  self.driver = [[TeakOperationTestDriver alloc] init];
}

- (void)tearDown {
  [self runWaitingBlocks];
  currentSession = nil;
  [super tearDown];
}

// Runs whatever is waiting for an identified user against a session that can't build a request,
// so nothing a test left waiting outlives it.
- (void)runWaitingBlocks {
  TeakSession* session = mock([TeakSession class]);
  [given([session currentState]) willReturn:[TeakSession UserIdentified]];
  NSArray* blocks = nil;
  @synchronized(currentSessionMutex) {
    blocks = [[TeakSession whenUserIdIsReadyRunBlocks] copy];
    [[TeakSession whenUserIdIsReadyRunBlocks] removeAllObjects];
  }
  for (void (^block)(TeakSession*) in blocks) {
    block(session);
  }
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
  XCTAssertEqualObjects(result.status, @"error");
}

- (void)testResultOfOperationCancelledBeforeRunIsErrorResult {
  TeakOperation* op = [TeakOperation withResult:[[TeakOperationResult alloc] initWithStatus:@"ok" andErrors:nil]];
  [op cancel];

  TeakOperationResult* result = nil;
  XCTAssertNoThrow(result = [self.driver runSync:op]);
  XCTAssertTrue([result isKindOfClass:[TeakOperationResult class]]);
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

// With no identified user, request operations wait. Waiting must not hold a thread, and the
// queue must keep running other operations however many are waiting.
- (void)testWaitingRequestOperationsHoldNoThread {
  for (NSNumber* count in @[ @10, @64, @100 ]) {
    NSOperationQueue* queue = [[NSOperationQueue alloc] init];
    NSUInteger before = TeakTestThreadCount();
    NSMutableArray<TeakOperation*>* ops = [[NSMutableArray alloc] init];
    for (NSUInteger i = 0; i < count.unsignedIntegerValue; i++) {
      TeakOperation* op = [TeakOperation forEndpoint:@"/me/test" withPayload:@{}];
      [ops addObject:op];
      [queue addOperation:op];
    }
    [NSThread sleepForTimeInterval:1.0];
    NSUInteger waiting = TeakTestThreadCount();

    TeakOperation* later = [TeakOperation withResult:[[TeakOperationResult alloc] initWithStatus:@"ok" andErrors:nil]];
    XCTestExpectation* laterFinished = [[XCTKVOExpectation alloc] initWithKeyPath:@"isFinished" object:later expectedValue:@YES];
    [queue addOperation:later];
    XCTWaiterResult laterResult = [XCTWaiter waitForExpectations:@[ laterFinished ] timeout:2.0];

    NSLog(@"C2282 waiting=%@ threads before=%lu while waiting=%lu later op finished=%@", count, (unsigned long)before,
          (unsigned long)waiting, laterResult == XCTWaiterResultCompleted ? @"YES" : @"NO");
    XCTAssertLessThan((NSInteger)waiting - (NSInteger)before, 8, @"%@ waiting operations", count);
    XCTAssertEqual(laterResult, XCTWaiterResultCompleted, @"%@ waiting operations", count);
    for (TeakOperation* op in ops) {
      XCTAssertFalse(op.isFinished);
    }

    [self runWaitingBlocks];
    [queue waitUntilAllOperationsAreFinished];
  }
}

- (void)testCancelWaitingRequestOperationFinishes {
  TeakOperation* op = [TeakOperation forEndpoint:@"/me/test" withPayload:@{}];
  NSOperationQueue* queue = [[NSOperationQueue alloc] init];
  XCTestExpectation* executing = [[XCTKVOExpectation alloc] initWithKeyPath:@"isExecuting" object:op expectedValue:@YES];
  [queue addOperation:op];
  [self waitForExpectations:@[ executing ] timeout:2.0];

  XCTestExpectation* finished = [[XCTKVOExpectation alloc] initWithKeyPath:@"isFinished" object:op expectedValue:@YES];
  [op cancel];
  [self waitForExpectations:@[ finished ] timeout:2.0];

  TeakOperationResult* result = (TeakOperationResult*)[op result];
  XCTAssertTrue([result isKindOfClass:[TeakOperationResult class]]);
  XCTAssertTrue(result.error);
  XCTAssertEqualObjects(result.errors, @{@"operation" : @[ @"operation was canceled" ]});
}

// Once a user is identified, an operation cancelled while it waited sends nothing and keeps its
// cancelled result.
- (void)testCancelledWaitingRequestOperationIgnoresIdentify {
  TeakOperation* op = [TeakOperation forEndpoint:@"/me/test" withPayload:@{}];
  NSOperationQueue* queue = [[NSOperationQueue alloc] init];
  XCTestExpectation* executing = [[XCTKVOExpectation alloc] initWithKeyPath:@"isExecuting" object:op expectedValue:@YES];
  [queue addOperation:op];
  [self waitForExpectations:@[ executing ] timeout:2.0];
  [op cancel];
  [queue waitUntilAllOperationsAreFinished];

  [self runWaitingBlocks];

  TeakOperationResult* result = (TeakOperationResult*)[op result];
  XCTAssertEqualObjects(result.errors, @{@"operation" : @[ @"operation was canceled" ]});
}

// A request operation cancelled before it starts finishes without waiting for a user.
- (void)testRequestOperationCancelledBeforeRunFinishes {
  TeakOperation* op = [TeakOperation forEndpoint:@"/me/test" withPayload:@{}];
  [op cancel];

  TeakOperationResult* result = nil;
  XCTAssertNoThrow(result = [self.driver runSync:op]);
  XCTAssertTrue(op.isFinished);
  XCTAssertEqualObjects(result.errors, @{@"operation" : @[ @"operation was canceled" ]});
}

@end
