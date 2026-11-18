#import <XCTest/XCTest.h>
#import <objc/runtime.h>

#import "TeakConfiguration.h"
#import "TeakEvent.h"
#import "TeakHelpers.h"
#import "TeakRemoteConfiguration.h"
#import "TeakRequest+Internal.h"
#import "TeakSession.h"
#import <Teak/Teak.h>

extern TeakSession* currentSession;

@interface Teak (ReportTaskTesting)
+ (dispatch_queue_t)sessionReportQueue;
+ (void)setSessionReportQueue:(dispatch_queue_t)queue;
@end

@interface TeakSession (ReportTaskTesting)
@property (strong, atomic) NSString* serverSessionId;
@property (strong, nonatomic, readwrite) TeakRemoteConfiguration* remoteConfiguration;
@property (copy, atomic) void (^reportDurationClaimHook)(void);
@property (nonatomic) UIBackgroundTaskIdentifier backgroundUpdateTask;
+ (TeakSession*)currentSession;
- (BOOL)setState:(nonnull TeakState*)newState;
- (void)detachDeviceConfigurationObservers;
- (BOOL)resetReportDurationBlock;
- (UIBackgroundTaskIdentifier)beginReportBackgroundTask;
- (void)endReportBackgroundTask:(UIBackgroundTaskIdentifier)task;
@end

@interface TeakRequest (ReportTaskTesting)
- (void)reportTaskTest_transmitSend:(TeakRequestSend*)send;
@end

// Test-only swizzle on the real -transmitSend: records the send instead of hitting the network. Like
// the real one it gives the send a task once it's handed to the network, unless a test says the
// transmit failed first (the real one reports such a failure and returns). The request, its callback
// and -response:payload:withError:forSend: are production code.
static NSMutableArray<TeakRequestSend*>* reportTaskTest_transmits;
static BOOL reportTaskTest_transmitReachesNetwork;

@implementation TeakRequest (ReportTaskTesting)
- (void)reportTaskTest_transmitSend:(TeakRequestSend*)send {
  @synchronized(reportTaskTest_transmits) {
    [reportTaskTest_transmits addObject:send];
  }
  if (reportTaskTest_transmitReachesNetwork) {
    send.task = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:@"https://example.invalid"]];
  }
}
@end

// /session_stop is sent from the background queue, and the app can suspend as soon as it goes to the
// background. A background task has to hold it awake from the moment the session goes Expiring until
// the request is done. Each test holds the report queue suspended so nothing but the task is keeping
// the app awake.
@interface TeakSessionReportTaskTests : XCTestCase
@end

@implementation TeakSessionReportTaskTests

// -[TeakSession init] reads TeakConfiguration.configuration; seed it once (another test class may
// have configured it already).
+ (void)setUp {
  [super setUp];
  @try {
    [TeakConfiguration configureForAppId:@"test-app" andSecret:@"test-secret"];
  } @catch (NSException* exception) {
  }
}

+ (void)swapTransmit {
  Class cls = [TeakRequest class];
  method_exchangeImplementations(class_getInstanceMethod(cls, @selector(transmitSend:)),
                                 class_getInstanceMethod(cls, @selector(reportTaskTest_transmitSend:)));
}

- (void)setUp {
  [super setUp];
  currentSession = nil;
  reportTaskTest_transmits = [NSMutableArray array];
  reportTaskTest_transmitReachesNetwork = YES;
  [TeakSessionReportTaskTests swapTransmit];
}

- (void)tearDown {
  [TeakSessionReportTaskTests swapTransmit];
  [Teak setSessionReportQueue:nil];
  [currentSession detachDeviceConfigurationObservers];
  if (currentSession != nil) [TeakEvent removeEventHandler:currentSession];
  currentSession = nil;
  [super tearDown];
}

#pragma mark - Helpers

// A session with a server id, so going Expiring schedules /session_stop. Its report runs on a
// suspended queue until -releaseReportQueue:. `blackhole` keeps the request from being sent at all.
- (TeakSession*)sessionWithHeldReportQueue:(dispatch_queue_t*)outQueue
                                 blackhole:(BOOL)blackhole
                                 claimHook:(void (^)(TeakSession*))claimHook {
  dispatch_queue_t reportQueue = dispatch_queue_create("io.teak.test.reportTask", DISPATCH_QUEUE_SERIAL);
  dispatch_suspend(reportQueue);
  [Teak setSessionReportQueue:reportQueue];

  TeakSession* session = [TeakSession currentSession];
  session.serverSessionId = @"test-server-session";
  __weak TeakSession* weakSession = session;
  session.reportDurationClaimHook = ^{
    if (claimHook != nil) claimHook(weakSession);
  };
  [session.remoteConfiguration setValue:@{kTeakHostname : @{@"/session_stop" : @{@"blackhole" : @(blackhole)}}}
                                 forKey:@"endpointConfigurations"];
  *outQueue = reportQueue;
  return session;
}

// Runs the held report, and everything queued behind it.
- (void)releaseReportQueue:(dispatch_queue_t)queue {
  dispatch_resume(queue);
  dispatch_sync(queue, ^{
                });
}

- (BOOL)waitUntil:(BOOL (^)(void))condition timeout:(NSTimeInterval)timeout {
  NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
  while ([deadline timeIntervalSinceNow] > 0) {
    @autoreleasepool {
      if (condition()) return YES;
      [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
  }
  return condition();
}

- (NSUInteger)transmitCount {
  @synchronized(reportTaskTest_transmits) {
    return reportTaskTest_transmits.count;
  }
}

#pragma mark - Queue

// The global queues are singletons, so this is the default-QoS one and not the background or utility one.
- (void)testReportQueueIsDefaultQoS {
  [Teak setSessionReportQueue:nil];
  XCTAssertEqual([Teak sessionReportQueue], dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0));
}

#pragma mark - Task lifetime

// The task has to be open before the report runs: that's the only thing keeping the app awake while
// the report waits for the background queue.
- (void)testExpiringOpensBackgroundTaskBeforeReportRuns {
  dispatch_queue_t queue = nil;
  TeakSession* session = [self sessionWithHeldReportQueue:&queue blackhole:YES claimHook:nil];

  XCTAssertTrue([session setState:[TeakSession Expiring]]);
  XCTAssertNotEqual(session.backgroundUpdateTask, UIBackgroundTaskInvalid,
                    @"no background task was open while /session_stop waited on its queue");

  [self releaseReportQueue:queue];
}

// A report that sends nothing has no request to wait for, so the task ends as soon as the report
// has run, and is still open when the report is claimed.
- (void)testTaskEndsAfterReportWhenNothingIsInFlight {
  dispatch_queue_t queue = nil;
  __block int claims = 0;
  __block UIBackgroundTaskIdentifier openAtClaim = UIBackgroundTaskInvalid;
  TeakSession* session = [self sessionWithHeldReportQueue:&queue
                                                blackhole:YES
                                                claimHook:^(TeakSession* claiming) {
                                                  claims++;
                                                  openAtClaim = claiming.backgroundUpdateTask;
                                                }];
  XCTAssertTrue([session setState:[TeakSession Expiring]]);

  [self releaseReportQueue:queue];

  XCTAssertEqual(claims, 1);
  XCTAssertNotEqual(openAtClaim, UIBackgroundTaskInvalid, @"the task ended before the report was claimed");
  XCTAssertEqual([self transmitCount], 0u);
  XCTAssertEqual(session.backgroundUpdateTask, UIBackgroundTaskInvalid, @"the task was left open after the report ran");
}

// Handing the request to the network isn't the end of the report: the app can suspend with the
// request in flight. The task stays open until the request's reply comes back.
- (void)testTaskStaysOpenUntilTheStopRequestCompletes {
  dispatch_queue_t queue = nil;
  TeakSession* session = [self sessionWithHeldReportQueue:&queue blackhole:NO claimHook:nil];
  XCTAssertTrue([session setState:[TeakSession Expiring]]);

  [self releaseReportQueue:queue];

  XCTAssertEqual([self transmitCount], 1u, @"/session_stop was not sent");
  XCTAssertNotEqual(session.backgroundUpdateTask, UIBackgroundTaskInvalid,
                    @"the task ended while /session_stop was still in flight");

  TeakRequestSend* send = nil;
  @synchronized(reportTaskTest_transmits) {
    send = reportTaskTest_transmits.firstObject;
  }
  [send.request response:nil payload:@{} withError:nil forSend:send];
  XCTAssertTrue([self waitUntil:^{ return (BOOL)(session.backgroundUpdateTask == UIBackgroundTaskInvalid); } timeout:5.0],
                @"the task was left open after /session_stop completed");
}

// A send that fails before reaching the network is reported and returns, so the request never
// calls back. The task can't wait for a reply that isn't coming.
- (void)testTaskEndsWhenTheSendNeverReachesTheNetwork {
  dispatch_queue_t queue = nil;
  TeakSession* session = [self sessionWithHeldReportQueue:&queue blackhole:NO claimHook:nil];
  reportTaskTest_transmitReachesNetwork = NO;
  XCTAssertTrue([session setState:[TeakSession Expiring]]);

  [self releaseReportQueue:queue];

  XCTAssertEqual([self transmitCount], 1u, @"/session_stop was not attempted");
  XCTAssertEqual(session.backgroundUpdateTask, UIBackgroundTaskInvalid,
                 @"the task was left open for a send that never reached the network");
}

// Returning to the game cancels the pending report; its task must end then, not when the queue
// eventually runs the canceled block.
- (void)testCanceledReportEndsBackgroundTask {
  dispatch_queue_t queue = nil;
  __block int claims = 0;
  TeakSession* session = [self sessionWithHeldReportQueue:&queue
                                                blackhole:YES
                                                claimHook:^(TeakSession* claiming) {
                                                  claims++;
                                                }];
  XCTAssertTrue([session setState:[TeakSession Expiring]]);
  XCTAssertNotEqual(session.backgroundUpdateTask, UIBackgroundTaskInvalid);

  XCTAssertFalse([session resetReportDurationBlock]);
  XCTAssertEqual(session.backgroundUpdateTask, UIBackgroundTaskInvalid,
                 @"canceling the report left its background task open");

  [self releaseReportQueue:queue];
  XCTAssertEqual(claims, 0, @"a canceled report was sent");
  XCTAssertEqual(session.backgroundUpdateTask, UIBackgroundTaskInvalid);
}

// A task id that's no longer the recorded one is already ended; ending it again must leave the
// newer report's task alone.
- (void)testEndingAStaleTaskLeavesTheCurrentOneOpen {
  TeakSession* session = [TeakSession currentSession];

  UIBackgroundTaskIdentifier first = [session beginReportBackgroundTask];
  XCTAssertNotEqual(first, UIBackgroundTaskInvalid);
  [session resetReportDurationBlock];
  XCTAssertEqual(session.backgroundUpdateTask, UIBackgroundTaskInvalid);

  UIBackgroundTaskIdentifier second = [session beginReportBackgroundTask];
  XCTAssertNotEqual(second, first);
  XCTAssertEqual(session.backgroundUpdateTask, second);

  [session endReportBackgroundTask:first];
  XCTAssertEqual(session.backgroundUpdateTask, second, @"ending a stale task ended the current one");

  [session endReportBackgroundTask:second];
  XCTAssertEqual(session.backgroundUpdateTask, UIBackgroundTaskInvalid);
  [session endReportBackgroundTask:second];
}

@end
