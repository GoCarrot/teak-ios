#import <XCTest/XCTest.h>
#import <stdatomic.h>

#import "SKPaymentObserver.h"
#import "TeakAppConfiguration.h"
#import "TeakConfiguration.h"
#import "TeakDeviceConfiguration.h"
#import "TeakLink.h"
#import "TeakLog.h"
#import "TeakPushState.h"
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
// userProfile/stateChain, and TeakDeviceConfiguration's pushToken/liveActivityPushToStartToken/
// advertisingIdentifier/notificationDisplayEnabled) that carry signal on their own, and
// ThreadSanitizer-only serialization guards (the attribute-dict test and the ProductRequest
// active-requests test) that need the sanitizer to see the race at all. Both kinds run every commit,
// just on different lanes: the `test` lane skips this whole class to keep the fast per-commit signal
// quick — the crash repros are too slow (up to 2M iterations) for it, and the serialization tests
// need TSan anyway. The `test_race` lane runs all of them, every commit, with ThreadSanitizer attached
// for the tests that need it, and additionally gates tagged-build releases.
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

// pushToken/liveActivityPushToStartToken/advertisingIdentifier/notificationDisplayEnabled are
// public but readonly on TeakDeviceConfiguration. Re-declared here for full read-write access,
// same convention as TeakSession above.
@interface TeakDeviceConfiguration (RaceTripwire)
@property (strong, atomic, readwrite) NSString* pushToken;
@property (strong, atomic, readwrite) NSString* liveActivityPushToStartToken;
@property (strong, atomic, readwrite) NSString* advertisingIdentifier;
@property (strong, atomic, readwrite) NSString* notificationDisplayEnabled;
@end

// addActiveProductRequest:/removeActiveProductRequest: are private (declared only in
// SKPaymentObserver.m). Re-declared here so the test can drive the real synchronized mutation
// methods directly, rather than reconstructing the array access by hand.
@interface ProductRequest (RaceTripwire)
+ (void)addActiveProductRequest:(ProductRequest*)request;
+ (void)removeActiveProductRequest:(ProductRequest*)request;
@end

// stateChain is private (declared only in TeakPushState.m's class extension). Re-declared here
// for full read-write access, per the project convention of redeclaring internal properties in
// the test file rather than importing Teak+Internal.h (which doesn't expose it either).
@interface TeakPushState (RaceTripwire)
@property (strong, atomic) NSArray* stateChain;
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

// Construction-read regression guard (ThreadSanitizer). initForRaven:'s copy-read of "user" used
// to run concurrently with handleEvent:'s in-place mutation of the SAME payloadTemplate sub-dict —
// a much smaller window than the lifetime-aliasing race above, but the same container-race class.
// Thread A drives the real mutation path; thread B repeatedly constructs fresh reports, exercising
// the real copy-read on every call. Fixed (userContext published as an atomic immutable snapshot),
// the read is a lock-free getter grab that never touches a dict another thread is mutating, so
// TSan stays silent. Reverting to the shared-mutable-dict design re-opens the window and TSan
// reports a race on the dictionary.
- (void)testRavenReportConstructionDoesNotRaceUserIdMutation {
  TeakRaven* raven = [self makeRaven];

  [self raceBlockA:^{
    for (int i = 0; i < 8000; i++) {
      UserIdEvent* event = [[UserIdEvent alloc] initWithType:UserIdentified];
      event.userId = [NSString stringWithFormat:@"user-%d", i];
      [raven handleEvent:event];
    }
  }
            blockB:^{
              for (int i = 0; i < 8000; i++) {
                TeakRavenReport* report = [[TeakRavenReport alloc] initForRaven:raven message:@"test" additions:nil];
                (void)report;
              }
            }];
}

// TeakDeviceConfiguration strong-property use-after-free repro (CF over-release trap). pushToken/
// liveActivityPushToStartToken are reassigned from handleEvent on the event-processing queue;
// advertisingIdentifier from getAdvertisingInformation (init, the LifecycleActivate event queue, and
// a main-queue retry); notificationDisplayEnabled from the pushState operation queue's completion
// block. All four are read cross-thread by TeakSession's operation queue while building the identify
// payload (TeakSession.m's sendUserIdentifier/dispatchUserDataEvent). Same technique as the
// TeakSession properties above — all four are plain NSStrings, so no isa-touch needed. Green now
// (atomic).
- (void)testPushTokenIsAtomicUnderConcurrency {
  TeakDeviceConfiguration* config = [[TeakDeviceConfiguration alloc] init];
  const int N = 200000;
  [self raceBlockA:^{
    for (int i = 0; i < N; i++) {
      config.pushToken = [[NSString alloc] initWithFormat:@"race-pushtoken-value-%d", i];
    }
  }
            blockB:^{
              for (int i = 0; i < N; i++) {
                NSString* s = config.pushToken;
                (void)s.length;
              }
            }];
}

- (void)testLiveActivityPushToStartTokenIsAtomicUnderConcurrency {
  TeakDeviceConfiguration* config = [[TeakDeviceConfiguration alloc] init];
  const int N = 200000;
  [self raceBlockA:^{
    for (int i = 0; i < N; i++) {
      config.liveActivityPushToStartToken = [[NSString alloc] initWithFormat:@"race-liveactivitytoken-value-%d", i];
    }
  }
            blockB:^{
              for (int i = 0; i < N; i++) {
                NSString* s = config.liveActivityPushToStartToken;
                (void)s.length;
              }
            }];
}

- (void)testAdvertisingIdentifierIsAtomicUnderConcurrency {
  TeakDeviceConfiguration* config = [[TeakDeviceConfiguration alloc] init];
  const int N = 200000;
  [self raceBlockA:^{
    for (int i = 0; i < N; i++) {
      config.advertisingIdentifier = [[NSString alloc] initWithFormat:@"race-advertisingid-value-%d", i];
    }
  }
            blockB:^{
              for (int i = 0; i < N; i++) {
                NSString* s = config.advertisingIdentifier;
                (void)s.length;
              }
            }];
}

- (void)testNotificationDisplayEnabledIsAtomicUnderConcurrency {
  TeakDeviceConfiguration* config = [[TeakDeviceConfiguration alloc] init];
  const int N = 200000;
  [self raceBlockA:^{
    for (int i = 0; i < N; i++) {
      config.notificationDisplayEnabled = [[NSString alloc] initWithFormat:@"race-notificationdisplay-value-%d", i];
    }
  }
            blockB:^{
              for (int i = 0; i < N; i++) {
                NSString* s = config.notificationDisplayEnabled;
                (void)s.length;
              }
            }];
}

// TeakPushState.stateChain is written under @synchronized(self) in updateCurrentState: but read
// lock-free by cachedPushState and serializedStateChain. COW discipline means the writer already
// swaps in a whole new array rather than mutating in place — but the old array is still freed on
// swap, so a nonatomic-strong reassignment on one thread races a read+retain on another, same as
// serverSessionId/countryCode/userProfile above. The array itself is a plain object (not a
// CFString), and its element (a single string) is short-lived per iteration too, so — like
// userProfile — a shallow read (e.g. .count alone) risks a same-shaped-allocation false green;
// isa-touch via NSStringFromClass plus .count, at userProfile's higher iteration count, reproduces
// reliably. Uses a bare `[TeakPushState alloc]` (no -init) since the test only drives the
// stateChain accessor — -init would register a TeakEvent handler and spin up an operation queue
// neither of which this repro needs.
- (void)testStateChainIsAtomicUnderConcurrency {
  TeakPushState* pushState = [TeakPushState alloc];
  const int N = 2000000;
  [self raceBlockA:^{
    for (int i = 0; i < N; i++) {
      pushState.stateChain = @[ [[NSString alloc] initWithFormat:@"race-statechain-value-%d", i] ];
    }
  }
            blockB:^{
              for (int i = 0; i < N; i++) {
                NSArray* chain = pushState.stateChain;
                (void)NSStringFromClass([chain class]).length;
                (void)chain.count;
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

// ProductRequest active-requests serialization guard (ThreadSanitizer). +activeProductRequests backs
// a write-only keep-alive array: addObject: runs on the StoreKit payment-queue thread
// (+productRequestForSku:callback:) while removeObject: runs on the SKProductsRequest delegate thread
// (-productsRequest:didReceiveResponse:). Thread A adds fresh requests while thread B removes a
// pre-seeded batch, landing both mutations on the shared NSMutableArray at once. The fix wraps both
// call sites in @synchronized(ProductRequestActiveRequestsMutex), so TSan stays silent; removing that
// synchronization reports a race on the array. Green now, red on revert.
- (void)testProductRequestActiveRequestsIsSerializedUnderConcurrency {
  const int N = 8000;
  NSMutableArray* preSeeded = [NSMutableArray array];
  for (int i = 0; i < N; i++) {
    ProductRequest* request = [[ProductRequest alloc] init];
    [preSeeded addObject:request];
    [ProductRequest addActiveProductRequest:request];
  }

  [self raceBlockA:^{
    for (int i = 0; i < N; i++) {
      [ProductRequest addActiveProductRequest:[[ProductRequest alloc] init]];
    }
  }
            blockB:^{
              for (ProductRequest* request in preSeeded) {
                [ProductRequest removeActiveProductRequest:request];
              }
            }];
}

// TeakLink route-registry serialization regression guard (ThreadSanitizer). registerRoute writes the
// static route dictionary from any host thread with no threading contract, while handleDeepLink and
// routeNamesAndDescriptions enumerate it — the real contention window is a host registering routes
// lazily post-launch while the launch deep link resolves concurrently on the op queue. Each writer
// iteration registers a distinct route (a real key insertion, not a same-key overwrite) while the
// reader iterates the real handleDeepLink: and routeNamesAndDescriptions methods. The fix wraps the
// write and a copy-then-enumerate snapshot of the read in @synchronized on the registry; remove
// either side and TSan reports a race on the dictionary. Green now, red on revert.
- (void)testTeakLinkRouteRegistryIsSerializedUnderConcurrency {
  const int N = 4000;
  [self raceBlockA:^{
    for (int i = 0; i < N; i++) {
      [TeakLink registerRoute:[NSString stringWithFormat:@"/race-tripwire/route-%d", i]
                          name:@"race-tripwire"
                   description:@"race tripwire probe route"
                         block:^(NSDictionary* params){
                         }];
    }
  }
            blockB:^{
              for (int i = 0; i < N; i++) {
                NSURL* url = [NSURL URLWithString:[NSString stringWithFormat:@"race-tripwire://race-tripwire/probe-%d", i]];
                [TeakLink handleDeepLink:url];
                (void)[TeakLink routeNamesAndDescriptions].count;
              }
            }];
}

@end
