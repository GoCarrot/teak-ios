#import <XCTest/XCTest.h>

#import "TeakSession.h"
#import <objc/runtime.h>

// C-837: TeakSession.currentState and previousState are read in the currentSessionMutex
// lock domain (the class methods) but written under @synchronized(self). They must be
// declared `atomic` so a cross-domain read can't tear. A behavioral race test isn't
// feasible — on ARM64 aligned pointer reads don't actually tear, so the race is formal
// (UB / TSan-detectable) rather than observable. These tests instead pin the property
// declarations to atomic via the Objective-C runtime, and fail if either is reverted.
@interface TeakSessionLockingTests : XCTestCase
@end

@implementation TeakSessionLockingTests

// YES if the named property carries the nonatomic flag (the "N" token in its runtime
// attribute string), which would reintroduce the C-837 torn-read race.
- (BOOL)isNonatomicProperty:(const char*)name {
  objc_property_t property = class_getProperty([TeakSession class], name);
  XCTAssertTrue(property != NULL, @"TeakSession has no property named %s", name);
  if (property == NULL) return YES;
  NSString* attributes = @(property_getAttributes(property));
  return [[attributes componentsSeparatedByString:@","] containsObject:@"N"];
}

- (void)testCurrentStateIsAtomic {
  XCTAssertFalse([self isNonatomicProperty:"currentState"],
                 @"TeakSession.currentState must stay atomic — read under currentSessionMutex, written under @synchronized(self) (C-837)");
}

- (void)testPreviousStateIsAtomic {
  XCTAssertFalse([self isNonatomicProperty:"previousState"],
                 @"TeakSession.previousState must stay atomic — same cross-lock-domain access as currentState (C-837)");
}

@end
