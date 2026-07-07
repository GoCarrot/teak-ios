#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <stdatomic.h>

#import "TeakAppConfiguration.h"
#import "TeakDeviceConfiguration.h"
#import "TeakRemoteConfiguration.h"
#import "TeakRequest.h"
#import "TeakSession.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Set by Teak.m's +initForApplicationId:... flow; TeakRequest's common-payload
// construction reads it directly (extern, not via a session/config object), and
// a bare unit test never runs that flow. Declared here so -setUp can seed it --
// leaving it nil would make -initWithSession:... throw (nil value in a
// dictionary literal) the first time this file runs before anything else in
// the process has triggered that flow.
extern NSDictionary* TeakVersionDict;

// TeakBatchedRequest / TeakTrackEventBatchedRequest are private classes declared
// only inside TeakRequest.m; re-declare their shape here so the test can drive
// the real class/instance methods directly, per the project convention (see
// RaceTripwireTests.m's TeakRavenReport re-declaration).
@interface TeakBatchedRequest : TeakRequest
@property (nonatomic) BOOL sent;
@property (strong, nonatomic) NSMutableArray* callbacks;
@property (strong, nonatomic) NSMutableArray* batchContents;

- (BOOL)cancel;
- (void)sendNow;
- (void)prepareAndSend;

+ (nullable TeakBatchedRequest*)addRequestIntoBatch:(nonnull TeakBatchedRequest*)batchedRequest
                                         withSession:(nonnull TeakSession*)session
                                         forEndpoint:(nonnull NSString*)endpoint
                                         withPayload:(nonnull NSDictionary*)payload
                                         andCallback:(nullable TeakRequestResponse)callback;
@end

@interface TeakTrackEventBatchedRequest : TeakBatchedRequest
- (nonnull TeakBatchedRequest*)initWithSession:(nonnull TeakSession*)session;
+ (nonnull TeakTrackEventBatchedRequest*)currentBatchForSession:(nonnull TeakSession*)session;
@end

// Test-only swizzles on the real (production) -cancel and -reallyActuallySend.
//
// -cancel: when armed via +raceTest_armPauseAfterNextCancel, the NEXT call
// (and only that one) signals raceTest_cancelHappenedSem right after running
// the real cancel logic, then blocks (bounded) on raceTest_proceedSem. This
// forces a real second thread's call into the exact window a standalone
// -cancel-then-later-@synchronized gap would leave open, without needing two
// copies of the source to compare -- the same test runs red against the old
// shape and green against the fix.
//
// -reallyActuallySend: captures an immutable snapshot of what was actually
// about to transmit (self.payload[@"batch"], copied at this exact synchronous
// point, before any further mutation) instead of hitting the network. Reading
// batchContents.count after the fact can't tell late-appended-but-dropped
// apart from actually-sent, since payload["batch"] aliases the same array;
// this is the one point where "about to send" is unambiguous.
static dispatch_semaphore_t raceTest_cancelHappenedSem;
static dispatch_semaphore_t raceTest_proceedSem;
static BOOL raceTest_pauseArmed;
static NSMutableArray<NSArray*>* raceTest_sentBatchSnapshots;

@interface TeakBatchedRequest (RaceTest)
+ (void)raceTest_armPauseAfterNextCancel;
- (BOOL)raceTest_cancel;
- (void)raceTest_reallyActuallySend;
@end

@implementation TeakBatchedRequest (RaceTest)

+ (void)raceTest_armPauseAfterNextCancel {
  raceTest_pauseArmed = YES;
}

- (BOOL)raceTest_cancel {
  // Post-swizzle, this selector is the ORIGINAL -cancel implementation.
  BOOL result = [self raceTest_cancel];
  if (raceTest_pauseArmed) {
    raceTest_pauseArmed = NO;
    dispatch_semaphore_signal(raceTest_cancelHappenedSem);
    dispatch_semaphore_wait(raceTest_proceedSem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)));
  }
  return result;
}

- (void)raceTest_reallyActuallySend {
  NSArray* snapshot = [self.payload[@"batch"] copy];
  @synchronized(raceTest_sentBatchSnapshots) {
    [raceTest_sentBatchSnapshots addObject:snapshot];
  }
  // Deliberately do not call through -- no real network traffic from this test.
}

@end

@interface TeakBatchedRequestRaceTests : XCTestCase
@end

@implementation TeakBatchedRequestRaceTests

#pragma mark - Swizzle install/remove

+ (void)swizzleSelector:(SEL)a withSelector:(SEL)b onClass:(Class)cls {
  Method ma = class_getInstanceMethod(cls, a);
  Method mb = class_getInstanceMethod(cls, b);
  method_exchangeImplementations(ma, mb);
}

- (void)setUp {
  TeakVersionDict = @{@"sdk_version" : @"4.3.13-test"};
  raceTest_cancelHappenedSem = dispatch_semaphore_create(0);
  raceTest_proceedSem = dispatch_semaphore_create(0);
  raceTest_pauseArmed = NO;
  raceTest_sentBatchSnapshots = [NSMutableArray array];

  Class cls = NSClassFromString(@"TeakBatchedRequest");
  [TeakBatchedRequestRaceTests swizzleSelector:@selector(cancel) withSelector:@selector(raceTest_cancel) onClass:cls];
  [TeakBatchedRequestRaceTests swizzleSelector:@selector(reallyActuallySend) withSelector:@selector(raceTest_reallyActuallySend) onClass:cls];
}

- (void)tearDown {
  Class cls = NSClassFromString(@"TeakBatchedRequest");
  [TeakBatchedRequestRaceTests swizzleSelector:@selector(cancel) withSelector:@selector(raceTest_cancel) onClass:cls];
  [TeakBatchedRequestRaceTests swizzleSelector:@selector(reallyActuallySend) withSelector:@selector(raceTest_reallyActuallySend) onClass:cls];
}

#pragma mark - Fixtures

// A batch large enough (count) and slow enough (time) that appends in these
// tests schedule rather than send immediately -- only an explicit -sendNow or
// hitting the count limit triggers a real -prepareAndSend.
- (TeakSession*)makeMockSession {
  TeakAppConfiguration* appConfig = mock([TeakAppConfiguration class]);
  [given([appConfig appId]) willReturn:@"test-app-id"];
  [given([appConfig appVersion]) willReturn:@"1"];
  [given([appConfig appVersionName]) willReturn:@"1.0.0"];
  [given([appConfig bundleId]) willReturn:@"io.teak.test"];
  [given([appConfig isProduction]) willReturn:@NO];

  TeakDeviceConfiguration* deviceConfig = mock([TeakDeviceConfiguration class]);
  [given([deviceConfig platformString]) willReturn:@"iOS"];
  [given([deviceConfig deviceModel]) willReturn:@"iPhone-test"];
  [given([deviceConfig deviceId]) willReturn:@"test-device-id"];

  TeakRemoteConfiguration* remoteConfig = mock([TeakRemoteConfiguration class]);
  NSDictionary* endpointConfigurations = @{
    @"gocarrot.com" : @{
      @"/me/events" : @{
        @"batch" : @{@"count" : @100000, @"time" : @60.0}
      }
    }
  };
  [given([remoteConfig endpointConfigurations]) willReturn:endpointConfigurations];
  [given([remoteConfig dynamicParameters]) willReturn:@{}];

  TeakSession* session = mock([TeakSession class]);
  [given([session appConfiguration]) willReturn:appConfig];
  [given([session deviceConfiguration]) willReturn:deviceConfig];
  [given([session remoteConfiguration]) willReturn:remoteConfig];
  [given([session userId]) willReturn:nil];

  return session;
}

// Spin-barrier rendezvous (same technique as RaceTripwireTests.m's
// raceBlockA:blockB:): both blocks arrive, then bust out together so short
// loops still overlap for their full duration.
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

#pragma mark - S1: addRequestIntoBatch: cancel+append must be atomic vs. a concurrent sendNow

// Forced-interleaving repro for the cancel/append/sendNow race (dropped-request
// ordering bug -- no crash/TSan signal per RACE_TESTING.md, so this drives the
// real -cancel/-addRequestIntoBatch:/-sendNow and forces the exact old gap with
// a test-only pause rather than hoping a hammer loop hits the window.
//
// Sequence: append payload #1 normally (schedules a real dispatch_after send).
// Arm the pause, then on a background thread append payload #2 -- its -cancel
// call (real production code) fires, then blocks. While it's blocked, drive
// -sendNow (the exact call the KVO currentState observer makes) on a second
// thread and confirm it does NOT complete while payload #2's append is
// in-flight -- that's the atomicity the fix provides. Release the pause, let
// both finish, then assert the transmitted snapshot (captured by the
// -reallyActuallySend swizzle, immune to the batchContents/payload aliasing
// that would otherwise hide a late, too-late append) contains both payloads.
- (void)testAddRequestIntoBatchDoesNotDropPayloadRacingSendNow {
  TeakSession* session = [self makeMockSession];
  TeakTrackEventBatchedRequest* batch = [[TeakTrackEventBatchedRequest alloc] initWithSession:session];

  [TeakTrackEventBatchedRequest addRequestIntoBatch:batch
                                         withSession:session
                                         forEndpoint:@"/me/events"
                                         withPayload:@{@"action_type" : @"race", @"object_type" : @"first"}
                                         andCallback:nil];
  XCTAssertFalse(batch.sent, @"first append should only schedule, not send immediately");

  __block BOOL sendNowReturned = NO;
  XCTestExpectation* appendDone = [self expectationWithDescription:@"append #2 completed"];
  XCTestExpectation* sendNowDone = [self expectationWithDescription:@"sendNow completed"];

  [TeakBatchedRequest raceTest_armPauseAfterNextCancel];

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    [TeakTrackEventBatchedRequest addRequestIntoBatch:batch
                                           withSession:session
                                           forEndpoint:@"/me/events"
                                           withPayload:@{@"action_type" : @"race", @"object_type" : @"second"}
                                           andCallback:nil];
    [appendDone fulfill];
  });

  long cancelHappened = dispatch_semaphore_wait(raceTest_cancelHappenedSem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)));
  XCTAssertEqual(cancelHappened, 0L, @"append #2's -cancel should have run and signalled by now");

  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    [batch sendNow];
    sendNowReturned = YES;
    [sendNowDone fulfill];
  });

  // sendNow needs the same instance lock append #2 is holding while paused --
  // it must still be blocked a moment later. This is the structural proof:
  // red here (sendNowReturned already true) means the two are NOT mutually
  // exclusive and the fix's atomicity has regressed.
  usleep(200000);
  XCTAssertFalse(sendNowReturned, @"sendNow must stay blocked while append #2's cancel+append is atomically in-flight");

  dispatch_semaphore_signal(raceTest_proceedSem);

  [self waitForExpectations:@[appendDone, sendNowDone] timeout:5.0];

  NSArray* transmitted = raceTest_sentBatchSnapshots.firstObject;
  XCTAssertEqual(raceTest_sentBatchSnapshots.count, (NSUInteger)1, @"batch should transmit exactly once");
  XCTAssertEqual(transmitted.count, (NSUInteger)2, @"both payloads must be present in what was actually transmitted -- a dropped one means the cancel+append race reopened");
}

#pragma mark - S2: currentBatchForSession:'s .sent read must be serialized against -prepareAndSend's write

// .sent is written under the instance lock (-prepareAndSend) but was read
// under the class mutex alone in currentBatchForSession: -- a cross-lock-domain
// race TSan can see directly (a plain BOOL field access, not an ARC-managed
// pointer route through libobjc). Both blocks drive only the real
// currentBatchForSession:/-prepareAndSend production methods, so the race
// under test is exactly currentBatchForSession:'s own internal .sent check
// against prepareAndSend's write -- not an extra ad hoc .sent read from
// outside those methods, which no production caller ever performs (.sent is
// a private, nonatomic property; every real access already holds the
// instance lock) and would race regardless of this fix. Green with the read
// properly nested under the instance lock, red (TSan race report) if that
// nesting is reverted.
- (void)testCurrentBatchForSessionSentReadIsSerializedUnderConcurrency {
  TeakSession* session = [self makeMockSession];
  const int N = 8000;

  [self raceBlockA:^{
    for (int i = 0; i < N; i++) {
      TeakTrackEventBatchedRequest* batch = [TeakTrackEventBatchedRequest currentBatchForSession:session];
      [batch prepareAndSend];
    }
  }
            blockB:^{
              for (int i = 0; i < N; i++) {
                [TeakTrackEventBatchedRequest currentBatchForSession:session];
              }
            }];
}

#pragma mark - S4: the reply callback loop must be serialized against addRequestIntoBatch:'s append

// self.callbacks is an NSMutableArray mutated under @synchronized(batchedRequest)
// by -addRequestIntoBatch: and, pre-fix, iterated with no lock at all by the
// reply callback -- the mutable-container race class TSan is squarely built to
// catch. Drives the real -addRequestIntoBatch: append path concurrently with
// the real reply callback block (batch.callback, the exact block
// -initWithSession: installs) instead of a hand-rolled loop over the array.
- (void)testReplyCallbackIterationIsSerializedAgainstAppend {
  TeakSession* session = [self makeMockSession];
  TeakTrackEventBatchedRequest* batch = [[TeakTrackEventBatchedRequest alloc] initWithSession:session];
  const int N = 8000;

  [self raceBlockA:^{
    for (int i = 0; i < N; i++) {
      [TeakTrackEventBatchedRequest addRequestIntoBatch:batch
                                             withSession:session
                                             forEndpoint:@"/me/events"
                                             withPayload:@{@"action_type" : @"race", @"object_type" : [NSString stringWithFormat:@"o-%d", i]}
                                             andCallback:^(NSDictionary* reply){
                                             }];
    }
  }
            blockB:^{
              for (int i = 0; i < N; i++) {
                batch.callback(@{});
              }
            }];
}

@end
