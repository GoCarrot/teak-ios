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

// Race-detection tripwires. Each drives or introspects a real Teak type and pins a property or
// invariant that a detector can observe, so a red one is a live defect (or, for the regression
// guard, a reverted fix). The fast per-commit `test` lane skips this class — some tripwires assert
// an as-yet-unfixed invariant and so fail by design — while the `test_race` lane runs it under
// ThreadSanitizer on every commit, where a red tripwire means the defect it guards is still open.

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
  // Only the raven-report tripwire needs this configuration; the dict-serialization guard drives a
  // bare-alloc profile and the session-atomicity guard introspects the class.
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

// Attribute-dict serialization regression guard (ThreadSanitizer). Two threads drive the real setter
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

// Session strong-property atomicity guard (property introspection). The session reply block
// reassigns these strong properties on one queue while the duration/report path reads and uses them
// on another; nonatomic strong reassignment releases the prior object mid-read (use-after-free).
// Making them atomic hands the reader a retained snapshot. Red while they remain nonatomic.
- (void)testSessionStrongSessionPropertiesAreAtomic {
  for (NSString* name in @[ @"serverSessionId", @"countryCode", @"userProfile" ]) {
    XCTAssertFalse([self isNonatomicSessionProperty:name],
                   @"TeakSession.%@ must be atomic — it is reassigned on one queue and read+used on another; nonatomic strong releases the prior value mid-read", name);
  }
}

// Raven report dictionary-identity guard (identity). The report shallow-copies the raven's payload
// template, so its "user" entry is the SAME mutable dictionary the raven keeps mutating (on identify)
// while a report is being JSON-encoded. The report must own a distinct copy. Red until the report
// deep-copies.
- (void)testRavenReportDoesNotShareUserDict {
  TeakRaven* raven = [TeakRaven ravenForTeak:self.teakMock];
  TeakRavenReport* report = [[TeakRavenReport alloc] initForRaven:raven message:@"tripwire" additions:nil];
  XCTAssertNotIdentical(report.payload[@"user"], raven.payloadTemplate[@"user"],
                        @"report.payload[user] must be a distinct dictionary, not the raven's live mutable one");
}

// Two audited concurrency defects have no data race for a sanitizer to catch, so they get no
// tripwire here — a standalone reconstruction would assert on a model, not on Teak, and would stay
// green even if the real bug shipped. The detection techniques, confirmed workable, are recorded so
// the real guards can be built against production code when each fix lands:
//   - Lock-inversion deadlock: a watchdog-forced AB-BA ordering (hold both first-locks at a barrier,
//     then cross-lock) deadlocks deterministically; a timeout is the detection.
//   - Batch cancel/relock drop: a barrier that forces a concurrent send into the gap between the add
//     path's cancel and re-lock reproduces the silently-dropped request.

@end
