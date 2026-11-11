#import <XCTest/XCTest.h>

#import "TeakConfiguration.h"
#import "TeakEvent.h"
#import "TeakHelpers.h"
#import "TeakLaunchData.h"
#import "TeakRemoteConfiguration.h"
#import "TeakRequest.h"
#import "TeakSession.h"
#import "TeakUserProfile.h"
#import <Teak/Teak.h>

extern TeakSession* currentSession;
extern NSDictionary* TeakVersionDict;

@interface Teak (LifetimeTesting)
+ (dispatch_queue_t)operationQueue;
@end

@interface TeakSession (LifetimeTesting)
@property (strong, atomic, readwrite) TeakUserProfile* userProfile;
@property (strong, atomic) NSString* serverSessionId;
@property (strong, nonatomic, readwrite) TeakRemoteConfiguration* remoteConfiguration;
@property (copy, atomic) void (^reportDurationClaimHook)(void);
@property (strong, atomic) dispatch_queue_t reportDurationQueue;
+ (TeakSession*)currentSession;
+ (void)logoutReusingCurrentSession:(BOOL)reuseSession;
- (BOOL)setState:(nonnull TeakState*)newState;
- (void)detachDeviceConfigurationObservers;
- (void)userProfileReceived:(nullable NSDictionary*)userProfile;
@end

// A session that's been replaced must free. Each test drives a real replacement path and then waits
// on a weak reference: the session's own setup hands it to background work that lets go of it
// asynchronously, so the release is polled rather than checked once.
@interface TeakSessionLifetimeTests : XCTestCase
@end

@implementation TeakSessionLifetimeTests

static NSDictionary* savedTeakVersionDict = nil;

// -[TeakSession init] reads TeakConfiguration.configuration; seed it once (another test class may
// have configured it already).
+ (void)setUp {
  [super setUp];
  @try {
    [TeakConfiguration configureForAppId:@"test-app" andSecret:@"test-secret"];
  } @catch (NSException* exception) {
  }
  // Set by Teak's own init, which tests don't run. A TeakRequest's common payload includes it, and
  // building that payload with it nil throws mid-init — which, without ARC exception cleanup, leaks
  // the session the request was being built for.
  savedTeakVersionDict = TeakVersionDict;
  if (TeakVersionDict == nil) {
    TeakVersionDict = @{@"ios" : @"test"};
  }
}

+ (void)tearDown {
  TeakVersionDict = savedTeakVersionDict;
  [super tearDown];
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

// Gives a session a user profile the way the identify reply does. The profile holds its session.
- (void)attachUserProfileTo:(TeakSession*)session {
  session.userProfile = [[TeakUserProfile alloc] initForSession:session withDictionary:@{}];
  XCTAssertNotNil(session.userProfile);
}

#pragma mark - Replacement paths

- (void)testSessionReplacedByLogoutFrees {
  __weak TeakSession* weakSession = nil;
  @autoreleasepool {
    weakSession = [TeakSession currentSession];
    XCTAssertNotNil(weakSession);
    [TeakSession logoutReusingCurrentSession:NO];
  }

  XCTAssertTrue([self waitUntil:^{ return (BOOL)(weakSession == nil); } timeout:5.0],
                @"a session replaced on logout is still alive");
}

- (void)testSessionWithUserProfileReplacedByLogoutFrees {
  __weak TeakSession* weakSession = nil;
  @autoreleasepool {
    TeakSession* session = [TeakSession currentSession];
    [self attachUserProfileTo:session];
    weakSession = session;
    [TeakSession logoutReusingCurrentSession:NO];
  }

  XCTAssertTrue([self waitUntil:^{ return (BOOL)(weakSession == nil); } timeout:5.0],
                @"a session replaced on logout is kept alive by its user profile");
}

- (void)testSessionWithUserProfileReplacedByLaunchFrees {
  __weak TeakSession* weakSession = nil;
  @autoreleasepool {
    TeakSession* session = [TeakSession currentSession];
    [self attachUserProfileTo:session];
    // A launch replaces any session that's past Created.
    XCTAssertTrue([session setState:[TeakSession Expiring]]);
    weakSession = session;
    [TeakSession didLaunchWithData:[TeakLaunchDataOperation unattributed]];
    XCTAssertNotEqual([TeakSession currentSessionOrNil], session);
  }

  XCTAssertTrue([self waitUntil:^{ return (BOOL)(weakSession == nil); } timeout:5.0],
                @"a session replaced on launch is still alive");
}

- (void)testExpiredSessionWithUserProfileReplacedOnNextAccessFrees {
  __weak TeakSession* weakSession = nil;
  @autoreleasepool {
    TeakSession* session = [TeakSession currentSession];
    [self attachUserProfileTo:session];
    XCTAssertTrue([session setState:[TeakSession Expiring]]);
    XCTAssertTrue([session setState:[TeakSession Expired]]);
    weakSession = session;
    XCTAssertNotEqual([TeakSession currentSession], session);
  }

  XCTAssertTrue([self waitUntil:^{ return (BOOL)(weakSession == nil); } timeout:5.0],
                @"an expired session replaced on the next currentSession access is still alive");
}

#pragma mark - Duration report

// Logout takes the session to Expiring, which schedules /session_stop, and replaces it immediately.
// The report has to go out even though nothing else holds the session by the time it runs. The report
// queue is held suspended until everything else that was holding the session has let go.
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
  }

  // Give everything else holding the session time to let go, so the report is the only thing that
  // could still be keeping it alive when the queue resumes. With the hold in place the session stays
  // alive and this times out; without it the session frees here and the report finds it gone.
  [self waitUntil:^{ return (BOOL)(weakSession == nil); } timeout:1.0];

  dispatch_resume(reportQueue);
  XCTAssertEqual(dispatch_semaphore_wait(claimed, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0,
                 @"/session_stop was dropped: the session freed before its duration report ran");

  XCTAssertTrue([self waitUntil:^{ return (BOOL)(weakSession == nil); } timeout:5.0],
                @"the session is still alive after its duration report ran");
}

#pragma mark - Late identify reply

// The /users.json request holds the session until its reply runs, so the reply can land after
// replacement. It must not attach a profile, which would hold the session again.
- (void)testIdentifyReplyAfterReplacementDoesNotPinSession {
  __weak TeakSession* weakSession = nil;
  @autoreleasepool {
    TeakSession* session = [TeakSession currentSession];
    weakSession = session;
    [TeakSession logoutReusingCurrentSession:NO];

    // Land the reply after replacement has released the profile on the operation queue.
    dispatch_sync([Teak operationQueue], ^{
                  });
    [session userProfileReceived:@{}];
    XCTAssertNil(session.userProfile);
  }

  XCTAssertTrue([self waitUntil:^{ return (BOOL)(weakSession == nil); } timeout:5.0],
                @"an identify reply after replacement pinned the session");
}

#pragma mark - Event batches

// Same shape TrackEvent sends.
- (NSDictionary*)trackEventPayload {
  return @{@"action_type" : @"test_action", @"object_type" : @"test_object", @"duration" : @1, @"count" : @1};
}

// A tracked event goes into a /me/events batch that holds its session. Replacement takes the session
// to Expiring, which sends the batch; the next event starts a new batch. The old batch and its session
// must then both free.
- (void)testEventBatchFromReplacedSessionFrees {
  __weak TeakSession* weakSession = nil;
  __weak TeakRequest* weakBatch = nil;
  @autoreleasepool {
    TeakSession* session = [TeakSession currentSession];
    // The default endpoint configuration delays /me/events, so this schedules the batch.
    TeakRequest* batch = [TeakRequest requestWithSession:session
                                             forEndpoint:@"/me/events"
                                             withPayload:[self trackEventPayload]
                                                  method:TeakRequest_POST
                                                callback:nil];
    XCTAssertNotNil(batch);
    // Keep the send off the network.
    [batch setValue:@YES forKey:@"blackhole"];
    weakSession = session;
    weakBatch = batch;

    [TeakSession logoutReusingCurrentSession:NO];
    XCTAssertTrue([[batch valueForKey:@"sent"] boolValue], @"Expiring didn't send the batch");

    TeakRequest* nextBatch = [TeakRequest requestWithSession:[TeakSession currentSession]
                                                 forEndpoint:@"/me/events"
                                                 withPayload:[self trackEventPayload]
                                                      method:TeakRequest_POST
                                                    callback:nil];
    XCTAssertNotEqual(nextBatch, batch);
    [nextBatch setValue:@YES forKey:@"blackhole"];
  }

  // The canceled scheduled send still holds the batch until its delay (5s by default) elapses.
  XCTAssertTrue([self waitUntil:^{ return (BOOL)(weakBatch == nil); } timeout:10.0],
                @"a sent event batch is still alive");
  XCTAssertTrue([self waitUntil:^{ return (BOOL)(weakSession == nil); } timeout:5.0],
                @"a replaced session with a sent event batch is still alive");
}

@end
