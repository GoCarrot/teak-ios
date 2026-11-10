#import <XCTest/XCTest.h>

#import "TeakPushState.h"
#import <objc/runtime.h>

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

// YES if the named property carries the nonatomic flag (the "N" token in its runtime
// attribute string), which would reintroduce the torn-read race.
- (BOOL)isNonatomicProperty:(const char*)name {
  objc_property_t property = class_getProperty([TeakPushState class], name);
  XCTAssertTrue(property != NULL, @"TeakPushState has no property named %s", name);
  if (property == NULL) return YES;
  NSString* attributes = @(property_getAttributes(property));
  return [[attributes componentsSeparatedByString:@","] containsObject:@"N"];
}

- (void)testStateChainIsAtomic {
  XCTAssertFalse([self isNonatomicProperty:"stateChain"],
                 @"TeakPushState.stateChain must stay atomic — written under @synchronized(self) in updateCurrentState: while cachedPushState/serializedStateChain read it lock-free");
}

@end
