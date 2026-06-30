#import <XCTest/XCTest.h>

#import "TeakRemoteConfiguration.h"
#import "TeakSession.h"
#import "TeakWaitForDeepLink.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Set by Teak_Plant in production; we drive it directly so configureForSession:
// resolves the barrier and queue it reaches through [Teak sharedInstance].
extern Teak* _teakSharedInstance;

// Re-expose internals for testing rather than importing Teak+Internal.h.
@interface Teak ()
@property (strong, nonatomic) NSOperationQueue* _Nonnull operationQueue;
@property (strong, nonatomic) TeakWaitForDeepLink* _Nonnull waitForDeepLink;
@end

@interface TeakWaitForDeepLink ()
@property (strong, nonatomic) NSOperation* operation;
@end

@interface TeakRemoteConfiguration (Testing)
- (void)configureForSession:(nonnull TeakSession*)session;
@end

@interface TeakWaitForDeepLinkTests : XCTestCase
@end

@implementation TeakWaitForDeepLinkTests {
  Teak* _savedSharedInstance;
}

- (void)setUp {
  _savedSharedInstance = _teakSharedInstance;
}

- (void)tearDown {
  _teakSharedInstance = _savedSharedInstance;
}

#pragma mark - Primitive: the barrier gates dependent operations

// Guards the dependency wiring in -whenFinishedRun:. If it stops adding the
// barrier as a dependency, the gated op is ready immediately and this fails.
- (void)testWhenFinishedRunBlocksOperationUntilBarrierReleased {
  TeakWaitForDeepLink* wait = [[TeakWaitForDeepLink alloc] init];
  NSOperationQueue* queue = [[NSOperationQueue alloc] init];

  XCTestExpectation* ran = [self expectationWithDescription:@"gated op runs after the barrier is released"];
  NSOperation* gatedOp = [NSBlockOperation blockOperationWithBlock:^{
    [ran fulfill];
  }];

  [wait whenFinishedRun:gatedOp];
  [queue addOperation:gatedOp];

  // Barrier not yet released: the op has an unsatisfied dependency, so it is
  // neither ready nor run.
  XCTAssertFalse(gatedOp.ready, @"gated op must not be ready until the deep-link barrier is released");
  XCTAssertFalse(gatedOp.finished, @"gated op must not run until the deep-link barrier is released");

  [wait addToQueue:queue];

  [self waitForExpectations:@[ran] timeout:2.0];
}

// Guards the hasBeenAdded race fix: the barrier op must enqueue at most once
// (adding the same NSOperation to a queue twice throws).
- (void)testAddToQueueIsIdempotent {
  TeakWaitForDeepLink* wait = [[TeakWaitForDeepLink alloc] init];
  NSOperationQueue* queue = [[NSOperationQueue alloc] init];

  XCTAssertTrue([wait addToQueue:queue], @"first addToQueue: releases the barrier");
  XCTAssertFalse([wait addToQueue:queue], @"subsequent addToQueue: calls are no-ops");
}

#pragma mark - Behavior: remote config blocks until deep links are ready

// The C-384 guard: configureForSession: must gate the settings.json request on
// the deep-link barrier. Red if whenFinishedRun:configOp is removed. The barrier
// is deliberately left unreleased, so the configOp block never runs and no
// TeakRequest is sent.
- (void)testConfigureForSessionGatesSettingsRequestOnDeepLinkBarrier {
  _teakSharedInstance = [[Teak alloc] init];
  _teakSharedInstance.operationQueue = [[NSOperationQueue alloc] init];
  _teakSharedInstance.waitForDeepLink = [[TeakWaitForDeepLink alloc] init];

  // Captured by the configOp block but never messaged, since the block never runs.
  TeakSession* session = mock([TeakSession class]);

  TeakRemoteConfiguration* remoteConfig = [[TeakRemoteConfiguration alloc] init];
  [remoteConfig configureForSession:session];

  NSOperation* barrierOp = _teakSharedInstance.waitForDeepLink.operation;
  BOOL gated = NO;
  for (NSOperation* op in _teakSharedInstance.operationQueue.operations) {
    if ([op.dependencies containsObject:barrierOp]) {
      gated = YES;
      break;
    }
  }

  XCTAssertTrue(gated, @"configureForSession: must gate the settings.json request on the deep-link barrier");
}

@end
