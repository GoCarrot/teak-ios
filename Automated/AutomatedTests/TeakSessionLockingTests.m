#import <XCTest/XCTest.h>

#import "TeakSession.h"
#import <objc/runtime.h>

// Several TeakSession properties are accessed across lock boundaries and must stay `atomic`:
//
//   - currentState / previousState are read in the currentSessionMutex lock domain (the class
//     methods) but written under @synchronized(self), so atomic keeps a cross-domain read from
//     tearing.
//   - reportDurationBlock is created and freed (reset) under @synchronized(self), but its
//     background-queue body reads it lock-free to check for cancellation. atomic keeps that
//     read from retaining a pointer the setter is releasing out from under it (a use-after-free
//     seen in production as an EXC_BAD_ACCESS in dispatch_block_testcancel).
//   - countryCode / userProfile / serverSessionId are reassigned in the identify-reply request
//     callback while read cross-thread by the heartbeat queue and the duration-report background
//     block. See RaceTripwireTests.m for the dynamic use-after-free repro backing these three.
//
// A behavioral race test for currentState/previousState/reportDurationBlock isn't feasible — on
// ARM64 aligned pointer reads don't actually tear, so the race is formal (UB / TSan-detectable)
// rather than observable, and these tests instead pin the declarations to atomic via the
// Objective-C runtime, failing if any reverts. countryCode/userProfile/serverSessionId get the
// same static pin here as a cheap permanent guard, on top of the dynamic repro.
@interface TeakSessionLockingTests : XCTestCase
@end

@implementation TeakSessionLockingTests

// YES if the named property carries the nonatomic flag (the "N" token in its runtime
// attribute string), which would reintroduce the torn-read race.
- (BOOL)isNonatomicProperty:(const char*)name {
  objc_property_t property = class_getProperty([TeakSession class], name);
  XCTAssertTrue(property != NULL, @"TeakSession has no property named %s", name);
  if (property == NULL) return YES;
  NSString* attributes = @(property_getAttributes(property));
  return [[attributes componentsSeparatedByString:@","] containsObject:@"N"];
}

- (void)testCurrentStateIsAtomic {
  XCTAssertFalse([self isNonatomicProperty:"currentState"],
                 @"TeakSession.currentState must stay atomic — read under currentSessionMutex, written under @synchronized(self)");
}

- (void)testPreviousStateIsAtomic {
  XCTAssertFalse([self isNonatomicProperty:"previousState"],
                 @"TeakSession.previousState must stay atomic — same cross-lock-domain access as currentState");
}

- (void)testReportDurationBlockIsAtomic {
  XCTAssertFalse([self isNonatomicProperty:"reportDurationBlock"],
                 @"TeakSession.reportDurationBlock must stay atomic — its background-queue body reads it outside @synchronized(self) while resetReportDurationBlock cancels and frees it under the lock");
}

- (void)testCountryCodeIsAtomic {
  XCTAssertFalse([self isNonatomicProperty:"countryCode"],
                 @"TeakSession.countryCode must stay atomic — reassigned in the identify-reply callback while sendHeartbeat reads it on the heartbeat queue");
}

- (void)testUserProfileIsAtomic {
  XCTAssertFalse([self isNonatomicProperty:"userProfile"],
                 @"TeakSession.userProfile must stay atomic — reassigned in the identify-reply callback while read and sent on the operation queue");
}

- (void)testServerSessionIdIsAtomic {
  XCTAssertFalse([self isNonatomicProperty:"serverSessionId"],
                 @"TeakSession.serverSessionId must stay atomic — reassigned in the identify-reply callback while read by the duration-report background block");
}

@end
