#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <stdatomic.h>

#import "TeakAppConfiguration.h"
#import "TeakConfiguration.h"
#import "TeakDeviceConfiguration.h"
#import "TeakLog.h"
#import "TeakRaven.h"
#import "TeakSession.h"
#import "TeakUserProfile.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Race-detection tripwires. Each reconstructs a known concurrency defect and pins a property or
// invariant that a detector can observe. This whole class is skipped by the per-commit Automated
// run — several tripwires assert an as-yet-unfixed invariant and so fail by design — and is run
// under ThreadSanitizer by the nightly `test_race` lane, where a red tripwire means the defect it
// guards is still open.
//
// Two kinds live here, and they must not be confused:
//   - real-code guards drive or introspect production types directly. A red one is a live defect
//     (or, for the regression guard, a reverted fix).
//   - mechanism reconstructions prove a detection technique against a standalone model; they do NOT
//     touch production code and are NOT regression guards for any shipped fix. They pass by
//     reproducing the modeled failure.
// The PR description maps each test to its source defect and kind.

@interface Teak (RaceTripwire)
+ (dispatch_queue_t)operationQueue;
@property (strong, nonatomic) TeakConfiguration* _Nonnull configuration;
@property (strong, nonatomic) TeakLog* _Nonnull log;
@property (strong, nonatomic, readwrite) NSString* _Nonnull sdkVersion;
@end

@interface TeakUserProfile (RaceTripwire)
@property (strong, nonatomic) NSMutableDictionary* stringAttributes;
@end

@interface TeakRaven (RaceTripwire)
@property (strong, nonatomic) NSMutableDictionary* payloadTemplate;
@end

@interface TeakRavenReport : NSObject
- (id)initForRaven:(nonnull TeakRaven*)raven message:(nonnull NSString*)message additions:(NSDictionary*)additions;
@property (strong, nonatomic) NSMutableDictionary* payload;
@end

// A profile whose send is a no-op: the tripwire drives a bare-alloc profile that has no backing
// request or session, so the real send would reach into unrelated networking. The tripwire only
// needs the setter's dictionary access to run.
@interface RaceGuardUserProfile : TeakUserProfile
@end
@implementation RaceGuardUserProfile
- (void)send {
}
@end

@interface RaceTripwireTests : XCTestCase
@property (strong, nonatomic) Teak* teakMock;
@end

@implementation RaceTripwireTests

- (void)setUp {
  // Only the raven tripwire needs this; the others introspect the class or run standalone GCD.
  TeakDeviceConfiguration* deviceConfig = mock([TeakDeviceConfiguration class]);
  [given([deviceConfig deviceId]) willReturn:@"test-device-id"];
  TeakAppConfiguration* appConfig = mock([TeakAppConfiguration class]);
  [given([appConfig appId]) willReturn:@"test-app-id"];
  [given([appConfig appVersion]) willReturn:@"1"];
  [given([appConfig appVersionName]) willReturn:@"1.0.0"];
  [given([appConfig isProduction]) willReturn:@NO];
  TeakConfiguration* config = mock([TeakConfiguration class]);
  [given([config deviceConfiguration]) willReturn:deviceConfig];
  [given([config appConfiguration]) willReturn:appConfig];
  self.teakMock = mock([Teak class]);
  [given([self.teakMock sdkVersion]) willReturn:@"4.3.13-test"];
  [given([self.teakMock configuration]) willReturn:config];
  TeakLog* log = [[TeakLog alloc] initForTeak:self.teakMock withAppId:@"test"];
  [given([self.teakMock log]) willReturn:log];
}

// Spin-barrier rendezvous: both blocks arrive at the barrier, then bust out within nanoseconds of
// each other, so short loops still overlap for their full duration. A single-signal gate would let
// the second block finish before the first even woke — a false "no race".
- (void)raceBlockA:(void (^)(void))a blockB:(void (^)(void))b {
  dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
  dispatch_group_t group = dispatch_group_create();
  _Atomic(int)* ready = calloc(1, sizeof(_Atomic(int)));
  void (^rendezvous)(void) = ^{
    atomic_fetch_add(ready, 1);
    while (atomic_load(ready) < 2) {
    }
  };
  dispatch_group_async(group, q, ^{ rendezvous(); a(); });
  dispatch_group_async(group, q, ^{ rendezvous(); b(); });
  dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
  free(ready);
}

- (BOOL)isNonatomicSessionProperty:(NSString*)name {
  objc_property_t property = class_getProperty([TeakSession class], name.UTF8String);
  XCTAssertTrue(property != NULL, @"TeakSession has no property named %@", name);
  if (property == NULL) return YES;
  NSString* attributes = @(property_getAttributes(property));
  return [[attributes componentsSeparatedByString:@","] containsObject:@"N"];
}

#pragma mark - Real-code guards

// C-955 regression guard (real code, ThreadSanitizer). Two threads drive the real setter
// concurrently with changing values on the same key, so each call performs the guarded read AND the
// dictionary write. The fix hops every access onto the serial operationQueue, so TSan stays silent
// here; if that hop is removed the read and write land on these two caller threads at once and TSan
// reports a race on the dictionary. Green now, red on revert.
- (void)testUserProfileAttributeDictIsSerializedUnderConcurrency {
  RaceGuardUserProfile* profile = [[RaceGuardUserProfile alloc] init];
  profile.stringAttributes = [@{@"level" : @"seed"} mutableCopy];

  [self raceBlockA:^{
    for (int i = 0; i < 8000; i++) [profile setStringAttribute:[NSString stringWithFormat:@"a-%d", i] forKey:@"level"];
  }
            blockB:^{
              for (int i = 0; i < 8000; i++) [profile setStringAttribute:[NSString stringWithFormat:@"b-%d", i] forKey:@"level"];
            }];

  // Drain the queued setter blocks so none outlive the test.
  dispatch_sync([Teak operationQueue], ^{
  });
}

// U1 deterministic floor (real code, property introspection). The session reply block reassigns
// these strong properties on one queue while the duration/report path reads and uses them on
// another; nonatomic strong reassignment releases the prior object mid-read (use-after-free).
// Making them atomic hands the reader a retained snapshot. Red while they remain nonatomic.
- (void)testSessionStrongSessionPropertiesAreAtomic {
  for (NSString* name in @[ @"serverSessionId", @"countryCode", @"userProfile" ]) {
    XCTAssertFalse([self isNonatomicSessionProperty:name],
                   @"TeakSession.%@ must be atomic — it is reassigned on one queue and read+used on another; nonatomic strong releases the prior value mid-read", name);
  }
}

// U2 deterministic guard (real code, identity). The report shallow-copies the raven's payload
// template, so its "user" entry is the SAME mutable dictionary the raven keeps mutating (on
// identify) while a report is being JSON-encoded. The report must own a distinct copy. Red until
// the report deep-copies. No sanitizer, no flakiness.
- (void)testRavenReportDoesNotShareUserDict {
  TeakRaven* raven = [TeakRaven ravenForTeak:self.teakMock];
  TeakRavenReport* report = [[TeakRavenReport alloc] initForRaven:raven message:@"tripwire" additions:nil];
  XCTAssertNotIdentical(report.payload[@"user"], raven.payloadTemplate[@"user"],
                        @"report.payload[user] must be a distinct dictionary, not the raven's live mutable one");
}

#pragma mark - Mechanism reconstructions

// Deadlock-detection technique (mechanism, not production code). Dedicated lock objects reproduce a
// two-lock AB-BA ordering; a barrier forces both first-locks to be held before either reaches its
// second, so the inversion deadlocks deterministically. A watchdog timeout is the detection. Passes
// by catching the forced deadlock.
- (void)testForcedLockInversionIsCaughtByWatchdog {
  NSObject* lockOne = [NSObject new];
  NSObject* lockTwo = [NSObject new];
  dispatch_semaphore_t aHasFirst = dispatch_semaphore_create(0);
  dispatch_semaphore_t bHasFirst = dispatch_semaphore_create(0);
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

  dispatch_async(q, ^{ // path A: one → two
    @synchronized(lockOne) {
      dispatch_semaphore_signal(aHasFirst);
      dispatch_semaphore_wait(bHasFirst, DISPATCH_TIME_FOREVER);
      @synchronized(lockTwo) {
      }
    }
    dispatch_semaphore_signal(done);
  });
  dispatch_async(q, ^{ // path B: two → one
    @synchronized(lockTwo) {
      dispatch_semaphore_signal(bHasFirst);
      dispatch_semaphore_wait(aHasFirst, DISPATCH_TIME_FOREVER);
      @synchronized(lockOne) {
      }
    }
    dispatch_semaphore_signal(done);
  });

  long timedOut = dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC));
  XCTAssertNotEqual(timedOut, 0, @"barrier-forced AB-BA lock ordering must deadlock — the watchdog timeout is the detection");
}

// Check-then-act drop technique (mechanism, not production code). Models a batching path whose
// cancel and re-lock are separate critical sections: in the gap between them a concurrent send can
// flip the batch to "sent", so a request added after that flip lands in an already-shipped batch
// and is silently dropped. Access is fully lock-serialized, so no memory tool sees it — the barrier
// forces the interleaving and the assertion catches the drop. Passes by reproducing the drop.
- (void)testDroppedRequestReproducedByBarrieredInterleaving {
  NSObject* lock = [NSObject new];
  __block BOOL sent = NO;
  NSMutableArray* contents = [NSMutableArray array];
  __block NSMutableArray* shipped = nil;
  dispatch_semaphore_t aInGap = dispatch_semaphore_create(0);
  dispatch_semaphore_t bShipped = dispatch_semaphore_create(0);
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  dispatch_queue_t q = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);

  dispatch_async(q, ^{ // add path: cancel (crit 1), gap, then add under crit 2
    BOOL cancelled;
    @synchronized(lock) {
      cancelled = !sent;
    }
    XCTAssertTrue(cancelled);
    dispatch_semaphore_signal(aInGap);
    dispatch_semaphore_wait(bShipped, DISPATCH_TIME_FOREVER);
    @synchronized(lock) {
      [contents addObject:@"reqA"];
      if (!sent) {
        shipped = [contents mutableCopy];
        sent = YES;
      }
    }
    dispatch_semaphore_signal(done);
  });
  dispatch_async(q, ^{ // send path: ships whatever is batched, inside the add path's gap
    dispatch_semaphore_wait(aInGap, DISPATCH_TIME_FOREVER);
    @synchronized(lock) {
      if (!sent) {
        shipped = [contents mutableCopy];
        sent = YES;
      }
    }
    dispatch_semaphore_signal(bShipped);
    dispatch_semaphore_signal(done);
  });

  dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
  dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
  XCTAssertFalse([shipped containsObject:@"reqA"],
                 @"the barrier-forced cancel→relock interleaving must reproduce the dropped request");
}

@end
