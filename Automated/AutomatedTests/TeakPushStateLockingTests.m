#import <XCTest/XCTest.h>

#import "AtomicPropertyAssertions.h"
#import "TeakPushState.h"

// TeakPushState.stateChain is written under @synchronized(self) (updateCurrentState:) but read
// lock-free by cachedPushState and serializedStateChain. COW discipline means the writer swaps in
// a brand-new array rather than mutating in place, so the old array is freed on swap — a
// nonatomic-strong reassignment on one thread races a read+retain on another, retaining a pointer
// that's being freed underneath it. AtomicPropertySnapshotTests.m checks the getter's behavior
// (it hands back a retained snapshot); this test is the same cheap static pin used for
// TeakSession's atomic properties in TeakSessionLockingTests.m.
@interface TeakPushStateLockingTests : XCTestCase
@end

@implementation TeakPushStateLockingTests

- (void)testStateChainIsAtomic {
  XCTAssertTrue(isAtomicProperty([TeakPushState class], "stateChain"),
                 @"TeakPushState.stateChain must stay atomic — written under @synchronized(self) in updateCurrentState: while cachedPushState/serializedStateChain read it lock-free");
}

@end
