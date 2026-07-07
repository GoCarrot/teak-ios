#import <XCTest/XCTest.h>
#import <stdatomic.h>

#import "TeakAppConfiguration.h"
#import "TeakConfiguration.h"
#import "TeakDeviceConfiguration.h"
#import "TeakLog.h"
#import "TeakRaven.h"
#import "TeakSession.h"
#import "TeakUserProfile.h"
#import "UserIdEvent.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Race-detection regression guard. Drives a real Teak type under concurrency and pins an invariant a
// detector can observe, so a red run means a real regression — the fix it guards was reverted. Two
// kinds of guard live here: deterministic CF-over-release crash repros (serverSessionId/countryCode/
// userProfile) that carry signal on their own, and a ThreadSanitizer-only serialization guard (the
// attribute-dict test) that needs the sanitizer to see the race at all. Both run every commit, just
// on different lanes: the `test` lane skips this whole class to keep the fast per-commit signal
// quick — the crash repros are too slow (up to 2M iterations) for it, and the serialization test
// needs TSan anyway. The `test_race` lane runs all of them, every commit, with ThreadSanitizer
// attached for the one test that needs it, and additionally gates tagged-build releases.
//
// See Automated/RACE_TESTING.md for the race-testing methodology — which detector catches which
// race class, and why some classes (e.g. lock-inversion deadlocks) get no in-process guard here.

@interface Teak (RaceTripwire)
+ (dispatch_queue_t)operationQueue;
@end

// Re-expose internal Teak properties needed to build a real TeakRaven (mirrors TeakRavenTests.m).
@interface Teak ()
@property (strong, nonatomic) TeakConfiguration* _Nonnull configuration;
@property (strong, nonatomic) TeakLog* _Nonnull log;
@end

// TeakRavenReport is a private class declared only inside TeakRaven.m; re-declare its shape here so
// the tripwire can drive the real initializer and inspect the resulting payload.
@interface TeakRavenReport : NSObject
@property (strong, nonatomic) NSMutableDictionary* payload;
- (id)initForRaven:(nonnull TeakRaven*)raven message:(nonnull NSString*)message additions:(NSDictionary*)additions;
@end

// userId is read-only in the public header; re-expose as read-write so the tripwire can construct
// UserIdEvent instances directly, the same way TeakRaven's own handleEvent: receives them.
@interface UserIdEvent ()
@property (strong, nonatomic, readwrite) NSString* _Nonnull userId;
@end

@interface TeakUserProfile (RaceTripwire)
@property (strong, nonatomic) NSMutableDictionary* stringAttributes;
@end

// countryCode/serverSessionId are private (declared only in TeakSession.m's class extension);
// userProfile is public but readonly there. Re-declared here for full read-write access, per the
// project convention of redeclaring internal properties in the test file rather than importing
// Teak+Internal.h.
@interface TeakSession (RaceTripwire)
@property (strong, atomic) NSString* countryCode;
@property (strong, atomic) NSString* serverSessionId;
@property (strong, atomic, readwrite) TeakUserProfile* userProfile;
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
@end

@implementation RaceTripwireTests

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

// TeakSession's designated initializer (-init) registers KVO observers and an event handler that
// -dealloc unconditionally unregisters; skipping -init and then letting the instance deinit would
// itself crash (NSRangeException from removeObserver:forKeyPath: on a path never added). These
// tests only drive the atomic property accessors, not a fully wired-up session, so they construct
// a bare `[TeakSession alloc]` (no -init) and hold it in this array for the rest of the process's
// lifetime rather than let it deinit.
static NSMutableArray* keepAliveBareSessions;

- (TeakSession*)bareSessionKeptAlive {
  if (keepAliveBareSessions == nil) {
    keepAliveBareSessions = [NSMutableArray array];
  }
  TeakSession* session = [TeakSession alloc];
  [keepAliveBareSessions addObject:session];
  return session;
}

// Session strong-property use-after-free repro (CF over-release trap). countryCode, userProfile,
// and serverSessionId are reassigned in the identify-reply request callback while read cross-thread
// by the heartbeat queue and the duration-report background block. A nonatomic strong reassignment
// on one thread races a read+retain on another, retaining a pointer that's being freed underneath
// it. See Automated/RACE_TESTING.md §3 for the technique this drives: fresh, distinct >15-char
// heap-allocated values on the writer side (short NSStrings become tagged pointers that never
// free, giving a false green), a spin-barrier so both threads race for their full duration, and a
// dereference (not just a pointer bind) on the reader side so a use-after-free lands inside the
// freed object. Green now (atomic).
- (void)testServerSessionIdIsAtomicUnderConcurrency {
  TeakSession* session = [self bareSessionKeptAlive];
  const int N = 200000;
  [self raceBlockA:^{
    for (int i = 0; i < N; i++) {
      session.serverSessionId = [[NSString alloc] initWithFormat:@"race-serversessionid-value-%d", i];
    }
  }
            blockB:^{
              for (int i = 0; i < N; i++) {
                NSString* s = session.serverSessionId;
                (void)s.length;
              }
            }];
}

- (void)testCountryCodeIsAtomicUnderConcurrency {
  TeakSession* session = [self bareSessionKeptAlive];
  const int N = 200000;
  [self raceBlockA:^{
    for (int i = 0; i < N; i++) {
      session.countryCode = [[NSString alloc] initWithFormat:@"race-countrycode-value-%d", i];
    }
  }
            blockB:^{
              for (int i = 0; i < N; i++) {
                NSString* s = session.countryCode;
                (void)s.length;
              }
            }];
}

// userProfile's pointee is a plain object, not a CFString — reading .stringAttributes.count alone
// wasn't a reliable enough dereference to reproduce (freed memory quickly reused by the next
// same-shaped allocation reads back as "valid"); touching the isa via NSStringFromClass forces a
// class-table lookup that reliably traps on the freed/reused pointer, at a higher iteration count
// than the two NSString properties above needed. Confirmed both ways: crashes reliably with
// userProfile reverted to nonatomic, clean with atomic restored.
- (void)testUserProfileIsAtomicUnderConcurrency {
  TeakSession* session = [self bareSessionKeptAlive];
  const int N = 2000000;
  [self raceBlockA:^{
    for (int i = 0; i < N; i++) {
      RaceGuardUserProfile* profile = [[RaceGuardUserProfile alloc] init];
      profile.stringAttributes = [@{@"seed" : [[NSString alloc] initWithFormat:@"race-userprofile-value-%d", i]} mutableCopy];
      session.userProfile = profile;
    }
  }
            blockB:^{
              for (int i = 0; i < N; i++) {
                TeakUserProfile* p = session.userProfile;
                (void)NSStringFromClass([p class]).length;
                (void)p.stringAttributes.count;
              }
            }];
}

// Builds a real TeakRaven the same way TeakRavenTests.m does: a fully-stubbed Teak mock so
// payloadTemplate construction runs to completion without touching the network.
- (TeakRaven*)makeRaven {
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

  Teak* teakMock = mock([Teak class]);
  [given([teakMock sdkVersion]) willReturn:@"4.3.13-test"];
  [given([teakMock configuration]) willReturn:config];
  [given([teakMock log]) willReturn:[[TeakLog alloc] initForTeak:teakMock withAppId:@"test"]];

  return [TeakRaven ravenForTeak:teakMock];
}

// Raven-report shared-dict regression guard (ThreadSanitizer). TeakRavenReport shallow-copies
// TeakRaven's payloadTemplate at initForRaven: — a plain top-level dictionaryWithDictionary: copy,
// which leaves nested mutable values (the "user" dict) as the SAME object referenced by both the
// live template and the report. Thread A drives the real UserIdentified mutation path
// (handleEvent:), which writes into that "user" dict on every call; thread B reads directly from
// the report's copy of it via objectForKey: — a stand-in for send's NSJSONSerialization read,
// which doesn't trip TSan's dictionary interceptor here, but pins the same aliasing invariant.
// Fixed, the report holds its own copy of "user" and the two threads touch different objects, so
// TSan stays silent. Reverting the fix re-aliases them and TSan reports a race on the dictionary.
- (void)testRavenReportDoesNotShareUserDict {
  TeakRaven* raven = [self makeRaven];
  TeakRavenReport* report = [[TeakRavenReport alloc] initForRaven:raven message:@"test" additions:nil];

  [self raceBlockA:^{
    for (int i = 0; i < 8000; i++) {
      UserIdEvent* event = [[UserIdEvent alloc] initWithType:UserIdentified];
      event.userId = [NSString stringWithFormat:@"user-%d", i];
      [raven handleEvent:event];
    }
  }
            blockB:^{
              for (int i = 0; i < 8000; i++) {
                (void)[report.payload[@"user"] objectForKey:@"device_id"];
              }
            }];
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

@end
