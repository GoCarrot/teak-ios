#import <XCTest/XCTest.h>

#import <Teak/Teak.h>

#import "TeakClaimPoll.h"
#import "TeakLaunchData.h"

@import OCHamcrest;
@import OCMockito;

@interface TeakNotificationLaunchData (Testing)
- (id)initWithUrl:(NSURL*)url;
@end

@interface TeakConfiguration : NSObject
+ (BOOL)configureForAppId:(NSString*)appId andSecret:(NSString*)appSecret;
@end

// Internal accessors for the in-flight claims dictionary and the
// reply-handling step, so the round-2 invariants (dedupe, cancel,
// stale-session drop) can be asserted against state, not behavior alone.
@interface TeakClaimPoll (Testing)
+ (NSMutableDictionary*)inflightClaims;
+ (void)handleClaimStatusReply:(NSDictionary*)reply forEventId:(NSString*)eventId;
@end

@interface ClaimStatusPollTests : XCTestCase
@end

@implementation ClaimStatusPollTests

+ (void)setUp {
  [super setUp];
  @try {
    [TeakConfiguration configureForAppId:@"test-app" andSecret:@"test-secret"];
  } @catch (NSException* e) {
    // Already initialized — fine.
  }
}

#pragma mark - Backoff schedule

/// First poll happens after the initial delay (~2s per spec).
- (void)testFirstPollUsesInitialDelay {
  NSTimeInterval delay = [TeakClaimPoll nextDelayAfter:0
                                          initialDelay:2.0
                                               ceiling:30.0];
  XCTAssertEqualWithAccuracy(delay, 2.0, 0.001);
}

/// Each subsequent attempt doubles the delay (exponential backoff).
- (void)testSubsequentPollsDoubleTheDelay {
  XCTAssertEqualWithAccuracy([TeakClaimPoll nextDelayAfter:1 initialDelay:2.0 ceiling:30.0], 4.0, 0.001);
  XCTAssertEqualWithAccuracy([TeakClaimPoll nextDelayAfter:2 initialDelay:2.0 ceiling:30.0], 8.0, 0.001);
  XCTAssertEqualWithAccuracy([TeakClaimPoll nextDelayAfter:3 initialDelay:2.0 ceiling:30.0], 16.0, 0.001);
}

/// Delay caps at the ceiling and never exceeds it, regardless of attempt count.
- (void)testDelayClampsToCeiling {
  // 2 * 2^4 = 32, exceeds 30s ceiling — must clamp.
  XCTAssertEqualWithAccuracy([TeakClaimPoll nextDelayAfter:4 initialDelay:2.0 ceiling:30.0], 30.0, 0.001);
  // Far past the ceiling: still clamped.
  XCTAssertEqualWithAccuracy([TeakClaimPoll nextDelayAfter:20 initialDelay:2.0 ceiling:30.0], 30.0, 0.001);
}

/// Helper accepts arbitrary base values — guards against hard-coded constants
/// (a future tunable could change initial/ceiling).
- (void)testBackoffIsParameterizedNotHardcoded {
  XCTAssertEqualWithAccuracy([TeakClaimPoll nextDelayAfter:0 initialDelay:1.0 ceiling:10.0], 1.0, 0.001);
  XCTAssertEqualWithAccuracy([TeakClaimPoll nextDelayAfter:3 initialDelay:1.0 ceiling:10.0], 8.0, 0.001);
  XCTAssertEqualWithAccuracy([TeakClaimPoll nextDelayAfter:5 initialDelay:1.0 ceiling:10.0], 10.0, 0.001);
}

#pragma mark - Terminal status detection

/// `pending` is the only non-terminal /claim_status response — keep polling.
- (void)testPendingIsNotTerminal {
  XCTAssertFalse([TeakClaimPoll isTerminalStatus:@"pending"]);
}

/// `completed` and `failed` are terminal — fire resolved event and stop.
- (void)testCompletedAndFailedAreTerminal {
  XCTAssertTrue([TeakClaimPoll isTerminalStatus:@"completed"]);
  XCTAssertTrue([TeakClaimPoll isTerminalStatus:@"failed"]);
}

/// Unknown / nil / empty values are treated as non-terminal so a malformed
/// reply doesn't lock the poll into an early exit. The poll's own retry/timeout
/// machinery handles network-level oddness.
- (void)testUnknownStatusIsNotTerminal {
  XCTAssertFalse([TeakClaimPoll isTerminalStatus:nil]);
  XCTAssertFalse([TeakClaimPoll isTerminalStatus:@""]);
  XCTAssertFalse([TeakClaimPoll isTerminalStatus:@"some_future_state"]);
}

#pragma mark - session_attribution mint (round-trip)

/// session_attribution is minted at click-request-build time as a JSON string
/// of launchData.to_h (the canonical wire shape from session_attribution_spec.md).
/// The blob must round-trip through JSON cleanly so the server can persist it.
- (void)testSessionAttributionMintRoundTripsForNotificationFixture {
  NSURL* url = [NSURL URLWithString:@"teaktest-app://chest?teak_notif_id=2048153148060669486&teak_schedule_id=2046986133304291328&teak_schedule_name=daily_promo_2026q2&teak_creative_id=2046986561123301779&teak_creative_name=summer_sale_v3&teak_reward_id=2048153148060669138&teak_channel_name=ios_push&teak_opt_out_category=teak"];
  TeakNotificationLaunchData* data = [[TeakNotificationLaunchData alloc] initWithUrl:url];

  NSString* blob = [TeakReward sessionAttributionStringFromLaunchData:data];
  XCTAssertNotNil(blob, @"mint must produce a non-nil JSON string");

  NSError* err = nil;
  NSDictionary* roundTripped = [NSJSONSerialization JSONObjectWithData:[blob dataUsingEncoding:NSUTF8StringEncoding]
                                                                options:0
                                                                  error:&err];
  XCTAssertNil(err);
  XCTAssertEqualObjects(roundTripped[@"teakNotifId"], @"2048153148060669486");
  XCTAssertEqualObjects(roundTripped[@"teakScheduleId"], @"2046986133304291328");
  XCTAssertEqualObjects(roundTripped[@"teakCreativeId"], @"2046986561123301779");
  XCTAssertEqualObjects(roundTripped[@"teakRewardId"], @"2048153148060669138");
  XCTAssertEqualObjects(roundTripped[@"teakChannelName"], @"ios_push");
  // Class-aware nulls present-but-null on a notification mint.
  XCTAssertEqualObjects(roundTripped[@"teakSystemActivityId"], [NSNull null]);
}

/// Mint from a nil launchData yields nil — caller (TeakReward) treats nil as
/// "omit the param from the click POST" rather than sending an empty blob.
- (void)testSessionAttributionMintReturnsNilForNilLaunchData {
  NSString* blob = [TeakReward sessionAttributionStringFromLaunchData:nil];
  XCTAssertNil(blob);
}

#pragma mark - Dedupe and lifecycle

/// Helper: drain the main queue so async dispatches from +startPollForEventId:
/// and +cancelAllPolls have a chance to run before the assertion.
- (void)drainMainQueue {
  XCTestExpectation* e = [self expectationWithDescription:@"main-queue drain"];
  dispatch_async(dispatch_get_main_queue(), ^{
    [e fulfill];
  });
  [self waitForExpectations:@[ e ] timeout:1.0];
}

/// First +startPollForEventId: records an in-flight claim; a second call
/// with the same eventId is a no-op (the existing claim continues, no
/// second entry). Cross-SDK dedupe contract: the SDK is responsible for
/// delivering each event_id exactly once.
- (void)testStartPollDedupesByEventId {
  [TeakClaimPoll cancelAllPolls];
  [self drainMainQueue];

  NSString* eventId = @"evt-dedupe-1";
  // Use a long initial delay so the timer can't fire before the assertion.
  [TeakClaimPoll startPollForEventId:eventId launchData:nil initialDelay:60.0 ceiling:120.0];
  [self drainMainQueue];

  id firstSlot = [TeakClaimPoll inflightClaims][eventId];
  XCTAssertNotNil(firstSlot, @"first start must record an in-flight claim for the event id");

  [TeakClaimPoll startPollForEventId:eventId launchData:nil initialDelay:60.0 ceiling:120.0];
  [self drainMainQueue];

  id secondSlot = [TeakClaimPoll inflightClaims][eventId];
  XCTAssertEqual(firstSlot, secondSlot,
                 @"re-entrant start with the same eventId must not replace the existing claim");
  XCTAssertEqual([TeakClaimPoll inflightClaims].count, (NSUInteger)1,
                 @"only one in-flight claim should be tracked");

  [TeakClaimPoll cancelAllPolls];
  [self drainMainQueue];
}

/// A reply for a claim whose originating session is no longer the current
/// session must drop the claim without firing TeakOnRewardClaimResolved.
/// In the test environment there's no live TeakSession, so the captured
/// originatingSession is nil at start-poll time — equivalent to the
/// production case where the originating session was deallocated post-
/// capture (logout/login swap, post-Expired session replacement). The
/// staleness check at reply time is the central round-2 correctness
/// invariant: it ensures a late reply never fires a resolved event against
/// a session the host game doesn't remember initiating.
- (void)testReplyForStaleClaimIsDropped {
  [TeakClaimPoll cancelAllPolls];
  [self drainMainQueue];

  NSString* eventId = @"evt-stale-1";
  [TeakClaimPoll startPollForEventId:eventId launchData:nil initialDelay:60.0 ceiling:120.0];
  [self drainMainQueue];

  XCTAssertNotNil([TeakClaimPoll inflightClaims][eventId],
                  @"start-poll must record the claim");

  [TeakClaimPoll handleClaimStatusReply:@{@"status" : @"completed", @"event_id" : eventId}
                             forEventId:eventId];
  [self drainMainQueue];

  XCTAssertNil([TeakClaimPoll inflightClaims][eventId],
               @"reply for a claim with no live originating session must drop the entry");
}

/// +cancelAllPolls clears the dictionary and invalidates pending timers.
/// Called from the Expired session transition; the click-time tracker is
/// abandoned in favor of the session-start sweep at next launch.
- (void)testCancelAllPollsClearsState {
  [TeakClaimPoll startPollForEventId:@"evt-cancel-1" launchData:nil initialDelay:60.0 ceiling:120.0];
  [TeakClaimPoll startPollForEventId:@"evt-cancel-2" launchData:nil initialDelay:60.0 ceiling:120.0];
  [self drainMainQueue];

  XCTAssertEqual([TeakClaimPoll inflightClaims].count, (NSUInteger)2);

  [TeakClaimPoll cancelAllPolls];
  [self drainMainQueue];

  XCTAssertEqual([TeakClaimPoll inflightClaims].count, (NSUInteger)0,
                 @"cancelAllPolls must clear the in-flight claims dictionary");
}

@end
