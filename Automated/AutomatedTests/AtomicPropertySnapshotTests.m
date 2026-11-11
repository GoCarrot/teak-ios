#import <XCTest/XCTest.h>
#import <objc/message.h>

#import "TeakChannelStatus.h"
#import "TeakPushState+Internal.h"
#import "TeakSession+Internal.h"
#import "TeakUserProfile.h"
#import <Teak/Teak.h>

// Snapshot-retention guards for atomic strong/copy properties whose pointee can be freed while
// another thread reads it. Each test checks that the real getter hands back a retained snapshot,
// which is what closes the cross-thread use-after-free (see Automated/RACE_TESTING.md §3b). They're
// single-threaded, deterministic and need no sanitizer, so they run in the fast `test` lane. The
// NSString-backed properties have two-thread CF-trap crash repros in RaceTripwireTests.m instead.

// The getter called with a non-retainable return type, so ARC adds no retain of its own and the
// result is exactly what the accessor handed back. There's no return-value-optimization handshake
// either, since that only happens when the caller is about to retain, so an atomic getter's
// autorelease really lands in the pool.
static void* (*const RawGetter)(id, SEL) = (void* (*)(id, SEL))objc_msgSend;
static void (*const Setter)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;

@interface AtomicPropertySnapshotTests : XCTestCase
@end

@implementation AtomicPropertySnapshotTests

// TeakSession's -init registers KVO observers and an event handler that -dealloc unconditionally
// unregisters, so a bare `[TeakSession alloc]` (no -init) would crash on deinit. These tests only
// drive the synthesized accessors, so they share one bare instance that lives for the process.
- (TeakSession*)bareSession {
  static TeakSession* session;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    session = [TeakSession alloc];
  });
  return session;
}

// Stands in the reader's load→retain gap: take the getter's result unretained, call the real setter,
// and check the old value survived. Red means the getter returned the bare ivar (nonatomic).
//
// makeValue must return a fresh heap object each call. A tagged pointer or shared singleton never
// frees, so it would pass forever; the final assertion catches that.
//
// This relies on the accessor being synthesized. A hand-written getter that loads the ivar and then
// retains it is still racy but would pass. Clang warns only when an atomic property pairs a
// hand-written getter with a synthesized setter, not when both are hand-written, and warnings
// aren't errors here, so don't count on the compiler to catch it.
- (void)assertGetter:(SEL)getter setter:(SEL)setter on:(id)object keepsSnapshotAliveOf:(id (^)(void))makeValue {
  __weak id oldValue;
  @autoreleasepool {
    Setter(object, setter, makeValue());  // the property is now the value's only owner
  }
  @autoreleasepool {
    oldValue = (__bridge id)RawGetter(object, getter);
    if (oldValue == nil) {
      XCTFail(@"seeded value should be readable back through %@", NSStringFromSelector(getter));
      return;
    }
    Setter(object, setter, makeValue());
    XCTAssertNotNil(oldValue, @"%@ freed the value a reader had just loaded — the getter didn't hand back a retained snapshot (is the property nonatomic?)", NSStringFromSelector(setter));
  }
  XCTAssertNil(oldValue, @"the replaced value outlived its snapshot — something else still owns it (a singleton or tagged pointer?), so this test can't go red");
}

// logListener's pointee is a block, a plain freeable object once it captures data and escapes to the
// heap. Host apps can reassign it from any thread at any time (it's the public "active log listener"
// property) while every SDK log call reads and invokes it on its own thread.
- (void)testLogListenerGetterReturnsRetainedSnapshot {
  Teak* teak = [[Teak alloc] init];
  [self assertGetter:@selector(logListener)
                setter:@selector(setLogListener:)
                    on:teak
  keepsSnapshotAliveOf:^id {
    NSString* tag = [[NSString alloc] initWithFormat:@"snapshot-loglistener-value-%u", arc4random()];
    // Capturing tag is load-bearing: a captureless block literal is __NSGlobalBlock__ (static,
    // never freed).
    return [^(NSString* event, NSString* level, NSDictionary* eventData) {
      (void)tag;
    } copy];
  }];
}

// TeakReward.onComplete is the same host-settable block shape as logListener: a public atomic copy
// property whose pointee is a freeable heap block. The reward-click reply callback (TeakReward.m)
// reads it into a single local before invoking, so this guards the property's atomicity itself, not
// a check-then-call double-read.
- (void)testOnCompleteGetterReturnsRetainedSnapshot {
  TeakReward* reward = [[TeakReward alloc] init];
  [self assertGetter:@selector(onComplete)
                setter:@selector(setOnComplete:)
                    on:reward
  keepsSnapshotAliveOf:^id {
    NSString* tag = [[NSString alloc] initWithFormat:@"snapshot-oncomplete-value-%u", arc4random()];
    // Capturing tag is load-bearing, same as logListener above.
    return [^{
      (void)tag;
    } copy];
  }];
}

// userProfile is reassigned in the identify-reply callback alongside countryCode/serverSessionId,
// and read by the heartbeat queue and the duration-report block.
- (void)testUserProfileGetterReturnsRetainedSnapshot {
  [self assertGetter:@selector(userProfile)
                setter:@selector(setUserProfile:)
                    on:[self bareSession]
  keepsSnapshotAliveOf:^id {
    return [[TeakUserProfile alloc] init];
  }];
}

// additionalData's pointee is an NSDictionary. A single non-empty entry forces a real heap-allocated
// dictionary; an empty dictionary literal returns a shared singleton that never deallocates.
- (void)testAdditionalDataGetterReturnsRetainedSnapshot {
  [self assertGetter:@selector(additionalData)
                setter:@selector(setAdditionalData:)
                    on:[self bareSession]
  keepsSnapshotAliveOf:^id {
    return @{@"seed" : [[NSString alloc] initWithFormat:@"snapshot-additionaldata-value-%u", arc4random()]};
  }];
}

// emailStatus/pushStatus/smsStatus are plain TeakChannelStatus objects. +unknown is a dispatch_once
// singleton that never deallocates; -[TeakChannelStatus initWithDictionary:] with a recognized state
// string gives a genuine fresh alloc on every call instead.
- (void)testEmailStatusGetterReturnsRetainedSnapshot {
  [self assertGetter:@selector(emailStatus)
                setter:@selector(setEmailStatus:)
                    on:[self bareSession]
  keepsSnapshotAliveOf:^id {
    return [[TeakChannelStatus alloc] initWithDictionary:@{@"state" : TeakChannelStateOptIn}];
  }];
}

- (void)testPushStatusGetterReturnsRetainedSnapshot {
  [self assertGetter:@selector(pushStatus)
                setter:@selector(setPushStatus:)
                    on:[self bareSession]
  keepsSnapshotAliveOf:^id {
    return [[TeakChannelStatus alloc] initWithDictionary:@{@"state" : TeakChannelStateOptIn}];
  }];
}

- (void)testSmsStatusGetterReturnsRetainedSnapshot {
  [self assertGetter:@selector(smsStatus)
                setter:@selector(setSmsStatus:)
                    on:[self bareSession]
  keepsSnapshotAliveOf:^id {
    return [[TeakChannelStatus alloc] initWithDictionary:@{@"state" : TeakChannelStateOptIn}];
  }];
}

// TeakPushState.stateChain is written under @synchronized(self) in updateCurrentState: but read
// lock-free by cachedPushState and serializedStateChain. The writer swaps in a whole new array
// (copy-on-write), and the old one is freed on swap. Uses a bare `[TeakPushState alloc]` (no -init),
// since -init would register a TeakEvent handler and spin up an operation queue this test doesn't
// need.
- (void)testStateChainGetterReturnsRetainedSnapshot {
  [self assertGetter:@selector(stateChain)
                setter:@selector(setStateChain:)
                    on:[TeakPushState alloc]
  keepsSnapshotAliveOf:^id {
    return @[ [[NSString alloc] initWithFormat:@"snapshot-statechain-value-%u", arc4random()] ];
  }];
}

@end
