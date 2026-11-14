#import <XCTest/XCTest.h>

#import "TeakConfiguration.h"
#import "TeakEvent.h"
#import "TeakHelpers.h"
#import "TeakRemoteConfiguration.h"
#import "TeakRequest.h"
#import "TeakSession.h"
#import <Teak/Teak.h>

extern TeakSession* currentSession;

@interface TeakSession (LifetimeTesting)
@property (strong, nonatomic, readwrite) TeakRemoteConfiguration* remoteConfiguration;
+ (TeakSession*)currentSession;
+ (void)logoutReusingCurrentSession:(BOOL)reuseSession;
- (void)detachDeviceConfigurationObservers;
@end

// blackhole is readwrite in TeakRequest+Internal.h; sent lives on the private batch subclass.
@interface TeakRequest (LifetimeTesting)
@property (nonatomic, readwrite) BOOL blackhole;
@property (nonatomic) BOOL sent;
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

#pragma mark - Event batches

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
