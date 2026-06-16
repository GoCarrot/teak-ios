#import <XCTest/XCTest.h>

#import "TeakSession.h"
#import "TeakState.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// The session pointer that whenUserIdIsReadyRun: / whenUserIdIsOrWasReadyRun:
// read. It has external linkage, so the test can drive it directly without
// standing up a real session (which performs network I/O at init).
extern TeakSession* currentSession;

// previousState is internal; re-expose it so the OrWas Expiring gate can be stubbed.
@interface TeakSession (Testing)
@property (strong, nonatomic) TeakState* previousState;
@end

@interface TeakSessionDeferredCallbackTests : XCTestCase
@end

@implementation TeakSessionDeferredCallbackTests

- (void)tearDown {
  currentSession = nil;
  [super tearDown];
}

// C-615: the deferred callback must run with the session that was current when
// it was *enqueued*, not whatever currentSession points at when the async block
// finally fires. Before the fix the block re-read the currentSession global
// after the @synchronized(currentSessionMutex) lock had been released, racing
// with reassignment — an unsynchronized objc_retain of the strong global that
// over-released the session and crashed a later access.
//
// This loops because it documents capture semantics rather than reproducing the
// data race: the fixed code passes deterministically every iteration, while the
// old re-read-the-global pattern almost always loses the race against the swap
// below and is caught well within the iteration count. A true crash repro needs
// ThreadSanitizer, which this project's schemes don't enable.
- (void)assertDeferredCaptureConfiguring:(void (^)(TeakSession*))configureSession
                                 enqueue:(void (^)(UserIdReadyBlock))enqueue {
  for (NSUInteger i = 0; i < 256; i++) {
    TeakSession* enqueued = mock([TeakSession class]);
    configureSession(enqueued);
    TeakSession* replacement = mock([TeakSession class]);

    currentSession = enqueued;

    XCTestExpectation* ran = [self expectationWithDescription:@"deferred callback ran"];
    __block TeakSession* received = nil;
    enqueue(^(TeakSession* session) {
      received = session;
      [ran fulfill];
    });

    // Swap the global out from under the just-enqueued callback. The fixed code
    // captured `enqueued` under the lock; the buggy code re-reads the global
    // here and hands the callback `replacement` instead.
    currentSession = replacement;

    [self waitForExpectations:@[ ran ] timeout:2.0];
    XCTAssertEqual(received, enqueued,
                   @"iteration %lu: callback saw a session swapped in after enqueue",
                   (unsigned long)i);
  }
}

- (void)testWhenUserIdIsReadyRunCapturesSessionAtEnqueue {
  [self assertDeferredCaptureConfiguring:^(TeakSession* session) {
    [given([session currentState]) willReturn:[TeakSession UserIdentified]];
  }
      enqueue:^(UserIdReadyBlock block) {
        [TeakSession whenUserIdIsReadyRun:block];
      }];
}

- (void)testWhenUserIdIsOrWasReadyRunCapturesSessionAtEnqueue {
  [self assertDeferredCaptureConfiguring:^(TeakSession* session) {
    [given([session currentState]) willReturn:[TeakSession UserIdentified]];
  }
      enqueue:^(UserIdReadyBlock block) {
        [TeakSession whenUserIdIsOrWasReadyRun:block];
      }];
}

// Exercises whenUserIdIsOrWasReadyRun:'s own gate — Expiring with a previous
// UserIdentified state — which the UserIdentified cases above don't reach.
- (void)testWhenUserIdIsOrWasReadyRunCapturesSessionWhileExpiring {
  [self assertDeferredCaptureConfiguring:^(TeakSession* session) {
    [given([session currentState]) willReturn:[TeakSession Expiring]];
    [given([session previousState]) willReturn:[TeakSession UserIdentified]];
  }
      enqueue:^(UserIdReadyBlock block) {
        [TeakSession whenUserIdIsOrWasReadyRun:block];
      }];
}

@end
