#import <XCTest/XCTest.h>

#import "TeakConfiguration.h"
#import "TeakEvent.h"
#import "TeakHelpers.h"
#import "TeakRemoteConfiguration.h"
#import "TeakRequest.h"
#import "TeakSession.h"
#import "TeakUserProfile.h"
#import <Teak/Teak.h>

extern TeakSession* currentSession;
extern NSDictionary* TeakVersionDict;

@interface TeakSession (LifetimeTesting)
@property (strong, atomic, readwrite) TeakUserProfile* userProfile;
@property (strong, atomic) NSString* serverSessionId;
@property (strong, nonatomic, readwrite) TeakRemoteConfiguration* remoteConfiguration;
@property (copy, atomic) void (^reportDurationClaimHook)(void);
@property (strong, atomic) dispatch_queue_t reportDurationQueue;
@property (nonatomic) BOOL deviceConfigurationObserversDetached;
+ (TeakSession*)currentSession;
+ (void)logoutReusingCurrentSession:(BOOL)reuseSession;
- (BOOL)setState:(nonnull TeakState*)newState;
- (void)userProfileReceived:(nullable NSDictionary*)userProfile;
- (void)detachDeviceConfigurationObservers;
@end

// blackhole is readwrite in TeakRequest+Internal.h; sent and -initWithSession: live on the private
// batch subclasses.
@interface TeakRequest (LifetimeTesting)
@property (nonatomic, readwrite) BOOL blackhole;
@property (nonatomic) BOOL sent;
- (instancetype)initWithSession:(TeakSession*)session;
@end

// Fails unless the weakly held object frees within the timeout.
#define AssertFreed(weakRef, timeoutSeconds, message) \
  XCTAssertTrue([self waitUntil:^{ return (BOOL)((weakRef) == nil); } timeout:(timeoutSeconds)], message)

// Objects tied to a session's lifetime must free once they're done. Each test drives a real path and
// then waits on a weak reference: background work lets go asynchronously, so the release is polled
// rather than checked once.
@interface TeakSessionLifetimeTests : XCTestCase
@end

@implementation TeakSessionLifetimeTests

// -[TeakSession init] reads TeakConfiguration.configuration; seed it once (another test class may
// have configured it already).
+ (void)setUp {
  [super setUp];
  @try {
    [TeakConfiguration configureForAppId:@"test-app" andSecret:@"test-secret"];
  } @catch (NSException* exception) {
  }
}

- (void)setUp {
  [super setUp];
  currentSession = nil;
}

- (void)tearDown {
  // A real session stays a live deviceConfiguration KVO observer and event handler until detached.
  [currentSession detachDeviceConfigurationObservers];
  if (currentSession != nil) [TeakEvent removeEventHandler:currentSession];
  currentSession = nil;
  [super tearDown];
}

#pragma mark - Helpers

// Spins until the condition holds or the timeout passes. Returns whether it held.
- (BOOL)waitUntil:(BOOL (^)(void))condition timeout:(NSTimeInterval)timeout {
  NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
  while ([deadline timeIntervalSinceNow] > 0) {
    @autoreleasepool {
      if (condition()) return YES;
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
  }
  @autoreleasepool {
    return condition();
  }
}

#pragma mark - Replacement paths

// An expired session is replaced on the next currentSession access. A replaced session must not stay
// a deviceConfiguration observer.
- (void)testExpiredSessionReplacedOnNextAccessDetaches {
  TeakSession* session = [TeakSession currentSession];
  XCTAssertTrue([session setState:[TeakSession Expiring]]);
  XCTAssertTrue([session setState:[TeakSession Expired]]);
  XCTAssertNotEqual([TeakSession currentSession], session);
  XCTAssertTrue(session.deviceConfigurationObserversDetached);
  [TeakEvent removeEventHandler:session];
}

#pragma mark - Duration report

// Logout takes the session to Expiring, which schedules /session_stop. The report has to go out even
// if nothing else holds the session by the time it runs. Sessions don't free on replacement yet, so
// the test drops the event-handler set's hold itself. The report queue is held suspended until
// everything else that was holding the session has let go.
- (void)testSessionReplacedByLogoutStillReportsDuration {
  dispatch_queue_t reportQueue = dispatch_queue_create("io.teak.test.reportDuration", DISPATCH_QUEUE_SERIAL);
  dispatch_suspend(reportQueue);
  dispatch_semaphore_t claimed = dispatch_semaphore_create(0);

  __weak TeakSession* weakSession = nil;
  @autoreleasepool {
    TeakSession* session = [TeakSession currentSession];
    session.serverSessionId = @"test-server-session";
    session.reportDurationQueue = reportQueue;
    session.reportDurationClaimHook = ^{
      dispatch_semaphore_signal(claimed);
    };
    // Keep /session_stop off the network.
    [session.remoteConfiguration setValue:@{kTeakHostname : @{@"/session_stop" : @{@"blackhole" : @YES}}}
                                   forKey:@"endpointConfigurations"];
    weakSession = session;
    [TeakSession logoutReusingCurrentSession:NO];
    [TeakEvent removeEventHandler:session];
  }

  // Lets every other holder of the session release it before the report runs.
  [self waitUntil:^{ return (BOOL)(weakSession == nil); } timeout:1.0];

  dispatch_resume(reportQueue);
  XCTAssertEqual(dispatch_semaphore_wait(claimed, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0,
                 @"/session_stop was dropped: the session freed before its duration report ran");

  AssertFreed(weakSession, 5.0, @"the session is still alive after its duration report ran");
}

#pragma mark - Late identify reply

// The /users.json request holds the session until its reply runs, so the reply can land after
// replacement. It must not attach a profile, which would hold the session again.
- (void)testIdentifyReplyAfterReplacementAttachesNoProfile {
  TeakSession* session = [TeakSession currentSession];
  [TeakSession logoutReusingCurrentSession:NO];

  [session userProfileReceived:@{}];
  XCTAssertNil(session.userProfile, @"an identify reply after replacement attached a profile");
  [TeakEvent removeEventHandler:session];
}

#pragma mark - Event batches

// A /me/events batch whose payload can't be built returns nil from init, before it registers as an
// observer of its session. Freeing that half-built batch must not try to remove the observer.
- (void)testEventBatchThatFailsToBuildFreesWithoutThrowing {
  TeakSession* session = [TeakSession currentSession];
  NSDictionary* versionDict = TeakVersionDict;
  // A nil value in the common payload is what makes building it fail.
  TeakVersionDict = nil;
  @try {
    XCTAssertNoThrow(({
                       @autoreleasepool {
                         TeakRequest* batch = [[NSClassFromString(@"TeakTrackEventBatchedRequest") alloc] initWithSession:session];
                         XCTAssertNil(batch);
                       }
                     }));
  } @finally {
    TeakVersionDict = versionDict;
  }
}

// Same shape TrackEvent sends.
- (NSDictionary*)trackEventPayload {
  return @{@"action_type" : @"test_action", @"object_type" : @"test_object", @"duration" : @1, @"count" : @1};
}

// A tracked event goes into a /me/events batch. Logout takes the session to Expiring, which sends the
// batch; the next event starts a new batch. The old batch must then free.
- (void)testSentEventBatchFrees {
  __weak TeakRequest* weakBatch = nil;
  @autoreleasepool {
    TeakSession* session = [TeakSession currentSession];
    // A short delay keeps the batch on the scheduled-send path without waiting out the 5s default.
    [session.remoteConfiguration setValue:@{kTeakHostname : @{@"/me/events" : @{@"batch" : @{@"time" : @0.1, @"count" : @50}}}}
                                   forKey:@"endpointConfigurations"];
    TeakRequest* batch = [TeakRequest requestWithSession:session
                                             forEndpoint:@"/me/events"
                                             withPayload:[self trackEventPayload]
                                                  method:TeakRequest_POST
                                                callback:nil];
    XCTAssertNotNil(batch);
    // Keep the send off the network.
    batch.blackhole = YES;
    weakBatch = batch;

    [TeakSession logoutReusingCurrentSession:NO];
    XCTAssertTrue(batch.sent, @"Expiring didn't send the batch");

    TeakRequest* nextBatch = [TeakRequest requestWithSession:[TeakSession currentSession]
                                                 forEndpoint:@"/me/events"
                                                 withPayload:[self trackEventPayload]
                                                      method:TeakRequest_POST
                                                    callback:nil];
    XCTAssertNotEqual(nextBatch, batch);
    nextBatch.blackhole = YES;
  }

  // The canceled scheduled send still holds the batch until its delay elapses.
  AssertFreed(weakBatch, 5.0, @"a sent event batch is still alive");
}

@end
