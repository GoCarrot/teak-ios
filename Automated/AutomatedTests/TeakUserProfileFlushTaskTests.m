#import <XCTest/XCTest.h>
#import <objc/runtime.h>

#import "TeakConfiguration.h"
#import "TeakEvent.h"
#import "TeakHelpers.h"
#import "TeakRemoteConfiguration.h"
#import "TeakRequest+Internal.h"
#import "TeakSession.h"
#import "TeakUserProfile.h"
#import <Teak/Teak.h>

extern TeakSession* currentSession;

static NSString* const ProfileFlushTaskName = @"io.teak.sdk.profileFlush";

@interface Teak (ProfileFlushTaskTesting)
+ (dispatch_queue_t)operationQueue;
@end

@interface TeakSession (ProfileFlushTaskTesting)
@property (strong, nonatomic, readwrite) TeakRemoteConfiguration* remoteConfiguration;
+ (TeakSession*)currentSession;
- (BOOL)setState:(nonnull TeakState*)newState;
- (void)detachDeviceConfigurationObservers;
- (void)userProfileReceived:(nullable NSDictionary*)userProfile;
@end

// Test-only swizzles. -transmitSend: records the send instead of hitting the network, and reports it
// handed to the network unless a test says otherwise. The UIApplication ones call through to the real
// methods and track which profile-flush tasks are open.
static NSMutableArray<TeakRequestSend*>* flushTaskTest_transmits;
static BOOL flushTaskTest_transmitReachesNetwork;
static NSMutableSet<NSNumber*>* flushTaskTest_openTasks;

@interface TeakRequest (ProfileFlushTaskTesting)
- (BOOL)flushTaskTest_transmitSend:(TeakRequestSend*)send;
@end

@implementation TeakRequest (ProfileFlushTaskTesting)
- (BOOL)flushTaskTest_transmitSend:(TeakRequestSend*)send {
  @synchronized(flushTaskTest_transmits) {
    [flushTaskTest_transmits addObject:send];
  }
  if (!flushTaskTest_transmitReachesNetwork) return NO;
  send.task = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:@"https://example.invalid"]];
  return YES;
}
@end

@interface UIApplication (ProfileFlushTaskTesting)
- (UIBackgroundTaskIdentifier)flushTaskTest_beginBackgroundTaskWithName:(NSString*)name expirationHandler:(void (^)(void))handler;
- (void)flushTaskTest_endBackgroundTask:(UIBackgroundTaskIdentifier)task;
@end

@implementation UIApplication (ProfileFlushTaskTesting)
- (UIBackgroundTaskIdentifier)flushTaskTest_beginBackgroundTaskWithName:(NSString*)name expirationHandler:(void (^)(void))handler {
  // Swapped, so this calls the real method.
  UIBackgroundTaskIdentifier task = [self flushTaskTest_beginBackgroundTaskWithName:name expirationHandler:handler];
  if ([name isEqualToString:ProfileFlushTaskName] && task != UIBackgroundTaskInvalid) {
    @synchronized(flushTaskTest_openTasks) {
      [flushTaskTest_openTasks addObject:@(task)];
    }
  }
  return task;
}

- (void)flushTaskTest_endBackgroundTask:(UIBackgroundTaskIdentifier)task {
  @synchronized(flushTaskTest_openTasks) {
    [flushTaskTest_openTasks removeObject:@(task)];
  }
  [self flushTaskTest_endBackgroundTask:task];
}
@end

// Going to the background flushes a pending player-profile update. The app can suspend while that
// flush waits on operationQueue or is in flight, so a background task has to hold it awake until the
// send is done. Tests hold operationQueue so nothing but the task is keeping the app awake.
@interface TeakUserProfileFlushTaskTests : XCTestCase
@property (strong, nonatomic) dispatch_semaphore_t operationQueueHold;
@property (strong, nonatomic) TeakRemoteConfiguration* configuredRemoteConfiguration;
@property (strong, nonatomic) NSDictionary* savedEndpointConfigurations;
@end

@implementation TeakUserProfileFlushTaskTests

+ (void)setUp {
  [super setUp];
  @try {
    [TeakConfiguration configureForAppId:@"test-app" andSecret:@"test-secret"];
  } @catch (NSException* exception) {
  }
}

+ (void)swapMethods {
  method_exchangeImplementations(class_getInstanceMethod([TeakRequest class], @selector(transmitSend:)),
                                 class_getInstanceMethod([TeakRequest class], @selector(flushTaskTest_transmitSend:)));
  method_exchangeImplementations(class_getInstanceMethod([UIApplication class], @selector(beginBackgroundTaskWithName:expirationHandler:)),
                                 class_getInstanceMethod([UIApplication class], @selector(flushTaskTest_beginBackgroundTaskWithName:expirationHandler:)));
  method_exchangeImplementations(class_getInstanceMethod([UIApplication class], @selector(endBackgroundTask:)),
                                 class_getInstanceMethod([UIApplication class], @selector(flushTaskTest_endBackgroundTask:)));
}

- (void)setUp {
  [super setUp];
  currentSession = nil;
  flushTaskTest_transmits = [NSMutableArray array];
  flushTaskTest_transmitReachesNetwork = YES;
  flushTaskTest_openTasks = [NSMutableSet set];
  [TeakUserProfileFlushTaskTests swapMethods];
}

- (void)tearDown {
  if (self.operationQueueHold != nil) [self releaseOperationQueue];
  NSSet<NSNumber*>* leftOpen;
  @synchronized(flushTaskTest_openTasks) {
    leftOpen = [flushTaskTest_openTasks copy];
  }
  for (NSNumber* task in leftOpen) {
    [[UIApplication sharedApplication] endBackgroundTask:task.unsignedIntegerValue];
  }
  [TeakUserProfileFlushTaskTests swapMethods];
  [self.configuredRemoteConfiguration setValue:self.savedEndpointConfigurations forKey:@"endpointConfigurations"];
  [currentSession detachDeviceConfigurationObservers];
  if (currentSession != nil) [TeakEvent removeEventHandler:currentSession];
  currentSession = nil;
  [super tearDown];
}

#pragma mark - Helpers

// A session whose profile has one attribute. The batch timer is long, so a change stays pending
// until something sends it.
- (TeakUserProfile*)profileForSession:(TeakSession*)session blackhole:(BOOL)blackhole {
  self.configuredRemoteConfiguration = session.remoteConfiguration;
  self.savedEndpointConfigurations = session.remoteConfiguration.endpointConfigurations;
  [session.remoteConfiguration setValue:@{kTeakHostname : @{@"/me/profile" : @{@"blackhole" : @(blackhole)}}}
                                 forKey:@"endpointConfigurations"];
  [session userProfileReceived:@{
    @"string_attributes" : @{@"level" : [NSNull null]},
    @"number_attributes" : @{},
    @"context" : @"test-context"
  }];
  TeakUserProfile* profile = session.userProfile;
  profile.batch.time = 600.0f;
  return profile;
}

- (void)setPendingUpdate:(TeakUserProfile*)profile value:(NSString*)value {
  [profile setStringAttribute:value forKey:@"level"];
  [self drainOperationQueue];
}

- (void)drainOperationQueue {
  dispatch_sync([Teak operationQueue], ^{
                });
}

// Takes the session Expiring with operationQueue held, checks the flush's task is open while it
// waits there, then lets the flush run.
- (void)flushOnExpiring:(TeakSession*)session {
  [self holdOperationQueue];
  XCTAssertTrue([session setState:[TeakSession Expiring]]);
  XCTAssertEqual([self openTaskCount], 1u, @"no background task was open while the flush waited on operationQueue");
  [self releaseOperationQueue];
}

- (void)holdOperationQueue {
  dispatch_semaphore_t hold = dispatch_semaphore_create(0);
  self.operationQueueHold = hold;
  dispatch_async([Teak operationQueue], ^{
    dispatch_semaphore_wait(hold, DISPATCH_TIME_FOREVER);
  });
}

// Runs everything queued behind the hold.
- (void)releaseOperationQueue {
  dispatch_semaphore_signal(self.operationQueueHold);
  self.operationQueueHold = nil;
  [self drainOperationQueue];
}

- (NSUInteger)openTaskCount {
  @synchronized(flushTaskTest_openTasks) {
    return flushTaskTest_openTasks.count;
  }
}

- (NSUInteger)transmitCount {
  @synchronized(flushTaskTest_transmits) {
    return flushTaskTest_transmits.count;
  }
}

- (TeakRequestSend*)lastTransmit {
  @synchronized(flushTaskTest_transmits) {
    return flushTaskTest_transmits.lastObject;
  }
}

- (void)replyTo:(TeakRequestSend*)send {
  [send.request response:nil payload:@{} withError:nil forSend:send];
}

// Flushes a pending update on Expiring, then fails the attempt with no reply, which schedules a
// retry. Returns once the retry is scheduled.
- (TeakRequestSend*)flushSendWaitingToRetry {
  TeakSession* session = [TeakSession currentSession];
  TeakUserProfile* profile = [self profileForSession:session blackhole:NO];
  [self setPendingUpdate:profile value:@"5"];

  [self flushOnExpiring:session];

  TeakRequestSend* send = [self lastTransmit];
  NSError* timedOut = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil];
  [send.request response:nil payload:@{} withError:timedOut forSend:send];
  NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
  while (send.socketErrorRetries == 0 && [deadline timeIntervalSinceNow] > 0) {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  }
  XCTAssertEqual(send.socketErrorRetries, 1u, @"the failed attempt wasn't scheduled for a retry");
  return send;
}

- (BOOL)waitForNoOpenTasks {
  NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
  while ([deadline timeIntervalSinceNow] > 0) {
    @autoreleasepool {
      if ([self openTaskCount] == 0) return YES;
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
  }
  return [self openTaskCount] == 0;
}

#pragma mark - Tests

- (void)testPendingUpdateHoldsTaskUntilItsReply {
  TeakSession* session = [TeakSession currentSession];
  TeakUserProfile* profile = [self profileForSession:session blackhole:NO];
  [self setPendingUpdate:profile value:@"5"];

  [self flushOnExpiring:session];
  XCTAssertEqual([self transmitCount], 1u, @"the pending update was not sent");
  XCTAssertEqual([self openTaskCount], 1u, @"the task ended while the profile send was in flight");

  [self replyTo:[self lastTransmit]];
  XCTAssertTrue([self waitForNoOpenTasks], @"the task was left open after the profile send completed");
}

- (void)testNothingPendingEndsTask {
  TeakSession* session = [TeakSession currentSession];
  [self profileForSession:session blackhole:NO];

  [self flushOnExpiring:session];
  XCTAssertEqual([self transmitCount], 0u);
  XCTAssertEqual([self openTaskCount], 0u, @"the task was left open with nothing to send");
}

// The earlier send carries the last update, so with nothing pending the flush waits on it.
- (void)testNothingPendingWaitsOnSendInFlight {
  TeakSession* session = [TeakSession currentSession];
  TeakUserProfile* profile = [self profileForSession:session blackhole:NO];
  [self setPendingUpdate:profile value:@"5"];
  [profile send];
  [self drainOperationQueue];
  XCTAssertEqual([self transmitCount], 1u);

  [self flushOnExpiring:session];
  XCTAssertEqual([self transmitCount], 1u);
  XCTAssertEqual([self openTaskCount], 1u, @"the task ended while the earlier send was still in flight");

  [self replyTo:[self lastTransmit]];
  XCTAssertTrue([self waitForNoOpenTasks], @"the task was left open after the earlier send completed");
}

// A newer send cancels the flush's send and carries its data, so the task moves to the newer send.
- (void)testSupersedingSendKeepsTaskUntilItsReply {
  TeakSession* session = [TeakSession currentSession];
  TeakUserProfile* profile = [self profileForSession:session blackhole:NO];
  [self setPendingUpdate:profile value:@"5"];

  [self flushOnExpiring:session];
  TeakRequestSend* flush = [self lastTransmit];

  [self setPendingUpdate:profile value:@"6"];
  [profile send];
  [self drainOperationQueue];
  XCTAssertEqual([self transmitCount], 2u);
  XCTAssertTrue(flush.cancelled);
  XCTAssertEqual([self openTaskCount], 1u, @"the task ended when its send was superseded");

  [self replyTo:[self lastTransmit]];
  XCTAssertTrue([self waitForNoOpenTasks], @"the task was left open after the superseding send completed");
}

// A failed attempt that gets retried isn't the end of the send, so the task stays open while the
// retry waits. Cancelling the send then means no reply will come.
- (void)testTaskStaysOpenAcrossRetryWaitAndEndsOnCancel {
  TeakRequestSend* send = [self flushSendWaitingToRetry];
  XCTAssertEqual([self openTaskCount], 1u, @"the task ended while the send waited to retry");

  [send cancel];
  XCTAssertEqual([self openTaskCount], 0u, @"cancelling the send while it waited to retry left its task open");
}

// A retry that never reaches the network has nothing left to wait for.
- (void)testRetryThatNeverReachesTheNetworkEndsTask {
  [self flushSendWaitingToRetry];
  flushTaskTest_transmitReachesNetwork = NO;

  XCTAssertTrue([self waitForNoOpenTasks], @"the task was left open after the retry failed to send");
  XCTAssertEqual([self transmitCount], 2u, @"the retry didn't run");
}

- (void)testBlackholedSendEndsTask {
  TeakSession* session = [TeakSession currentSession];
  TeakUserProfile* profile = [self profileForSession:session blackhole:YES];
  [self setPendingUpdate:profile value:@"5"];

  [self flushOnExpiring:session];

  XCTAssertEqual([self transmitCount], 0u);
  XCTAssertEqual([self openTaskCount], 0u, @"the task was left open for a blackholed send");
}

- (void)testSendThatNeverReachesTheNetworkEndsTask {
  TeakSession* session = [TeakSession currentSession];
  TeakUserProfile* profile = [self profileForSession:session blackhole:NO];
  [self setPendingUpdate:profile value:@"5"];
  flushTaskTest_transmitReachesNetwork = NO;

  [self flushOnExpiring:session];

  XCTAssertEqual([self transmitCount], 1u);
  XCTAssertEqual([self openTaskCount], 0u, @"the task was left open for a send that never reached the network");
}

@end
