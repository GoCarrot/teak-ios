#import <XCTest/XCTest.h>

#import <Teak/Teak.h>

#import "TeakClaimPoll.h"
#import "TeakLaunchData.h"
#import "TeakSession.h"

@import OCHamcrest;
@import OCMockito;

// Re-declare the in-flight claim's testable slots. The class itself is
// defined privately in TeakClaimPoll.m; the runtime resolves these
// properties dynamically when the test reads them off a dictionary value.
@interface TeakInflightClaim : NSObject
@property (nonatomic, copy, nullable) NSString* clickingUserId;
@property (nonatomic, copy) NSString* eventId;
@end

@interface TeakConfiguration : NSObject
+ (BOOL)configureForAppId:(NSString*)appId andSecret:(NSString*)appSecret;
@end

// Internal entry points the sweep dispatcher exposes for unit-level coverage.
// `dispatchSweptClaims:session:` is the wire-free seam — production callers
// reach it through `+startSweep`, which composes the GET /claims request and
// hands the parsed array off to this dispatcher.
@interface TeakClaimPoll (Testing)
+ (NSMutableDictionary*)inflightClaims;
+ (NSDictionary*)buildResolvedUserInfoForReply:(NSDictionary*)reply
                                withAttribution:(NSDictionary*)attribution;
+ (void)dispatchSweptClaims:(NSArray*)claims session:(id)session;
@end

@interface SessionStartSweepTests : XCTestCase
@end

@implementation SessionStartSweepTests

+ (void)setUp {
  [super setUp];
  @try {
    [TeakConfiguration configureForAppId:@"test-app" andSecret:@"test-secret"];
  } @catch (NSException* e) {
    // Already initialized — fine.
  }
}

- (void)setUp {
  [super setUp];
  [TeakClaimPoll cancelAllPolls];
  [self drainMainQueue];
}

- (void)tearDown {
  [TeakClaimPoll cancelAllPolls];
  [self drainMainQueue];
  [super tearDown];
}

- (void)drainMainQueue {
  XCTestExpectation* e = [self expectationWithDescription:@"main-queue drain"];
  dispatch_async(dispatch_get_main_queue(), ^{
    [e fulfill];
  });
  [self waitForExpectations:@[ e ] timeout:1.0];
}

#pragma mark - Resolved-userInfo build (dict-taking helper)

/// The dict-taking helper unpacks the eleven-key session_attribution blob and
/// merges it with the wire reply at fire time. Reply wins on key collision —
/// same merge order as the launchData-taking helper used by the click-time
/// path. The resolved-event userInfo surfaces only the attribution reward id
/// (`teakRewardId`), matching legacy `TeakOnReward` semantics; the wire's
/// authoritative-grant id is stripped before the merge (host games read the
/// `reward` blob for grant content).
- (void)testBuildResolvedUserInfoMergesAttributionDictAndReply {
  NSDictionary* attribution = @{
    @"launch_link" : @"teaktest-app://chest",
    @"teakNotifId" : @"2048153148060669486",
    @"teakScheduleId" : @"2046986133304291328",
    @"teakScheduleName" : @"daily_promo_2026q2",
    @"teakCreativeId" : @"2046986561123301779",
    @"teakCreativeName" : @"summer_sale_v3",
    @"teakRewardId" : @"2048153148060669138",
    @"teakChannelName" : @"ios_push",
    @"teakDeepLink" : [NSNull null],
    @"teakOptOutCategory" : @"teak",
    @"teakSystemActivityId" : [NSNull null],
  };
  NSDictionary* reply = @{
    @"event_id" : @"evt-resurfaced-1",
    @"status" : @"completed",
    @"reward" : @{@"gems" : @25},
    @"customer_response" : @"{\"ok\":true}",
    @"customer_status_code" : @200,
    @"teak_reward_id" : @"2048153148060669999",
  };

  NSDictionary* userInfo = [TeakClaimPoll buildResolvedUserInfoForReply:reply
                                                          withAttribution:attribution];
  XCTAssertNotNil(userInfo);
  XCTAssertEqualObjects(userInfo[@"event_id"], @"evt-resurfaced-1");
  XCTAssertEqualObjects(userInfo[@"status"], @"completed");
  XCTAssertEqualObjects(userInfo[@"reward"], @{@"gems" : @25});
  XCTAssertEqualObjects(userInfo[@"customer_status_code"], @200);

  XCTAssertEqualObjects(userInfo[@"teakNotifId"], @"2048153148060669486");
  XCTAssertEqualObjects(userInfo[@"teakScheduleId"], @"2046986133304291328");
  XCTAssertEqualObjects(userInfo[@"teakCreativeName"], @"summer_sale_v3");
  XCTAssertEqualObjects(userInfo[@"teakChannelName"], @"ios_push");

  // Attribution id surfaces; the wire's authoritative-grant id is stripped.
  XCTAssertEqualObjects(userInfo[@"teakRewardId"], @"2048153148060669138");
  XCTAssertNil(userInfo[@"teak_reward_id"]);
}

/// /claims (sweep) wire reply carries `created_at` and `completed_at` —
/// those server-emitted timing fields ride through to the resolved-event
/// userInfo on the sweep-terminal path so host games can render the
/// click→resolve timeline. /claim_status (click-time-poll) does not emit
/// these fields today; the click-time-poll path's strip set is covered in
/// JwtModeRewardEventsTests.m.
- (void)testBuildResolvedUserInfoSurfacesTimingFieldsFromClaimsReply {
  NSDictionary* attribution = @{
    @"teakNotifId" : @"2048153148060669486",
    @"teakRewardId" : @"2048153148060669138",
  };
  NSDictionary* claimsReply = @{
    @"event_id" : @"evt-sweep-timing-1",
    @"status" : @"completed",
    @"reward" : @{@"gems" : @25},
    @"created_at" : @"2026-04-28T17:00:00Z",
    @"completed_at" : @"2026-04-28T17:00:05Z",
  };

  NSDictionary* userInfo = [TeakClaimPoll buildResolvedUserInfoForReply:claimsReply
                                                          withAttribution:attribution];

  XCTAssertEqualObjects(userInfo[@"event_id"], @"evt-sweep-timing-1");
  XCTAssertEqualObjects(userInfo[@"created_at"], @"2026-04-28T17:00:00Z");
  XCTAssertEqualObjects(userInfo[@"completed_at"], @"2026-04-28T17:00:05Z");
}

/// Defensive: a nil attribution dict yields the wire reply alone. Mirrors the
/// nil-launchData defensive case on the click-time helper.
- (void)testBuildResolvedUserInfoWithNilAttributionReturnsReplyAlone {
  NSDictionary* reply = @{
    @"event_id" : @"evt-resurfaced-2",
    @"status" : @"failed",
  };
  NSDictionary* userInfo = [TeakClaimPoll buildResolvedUserInfoForReply:reply
                                                          withAttribution:nil];
  XCTAssertNotNil(userInfo);
  XCTAssertEqualObjects(userInfo[@"event_id"], @"evt-resurfaced-2");
  XCTAssertEqualObjects(userInfo[@"status"], @"failed");
  XCTAssertNil(userInfo[@"teakNotifId"]);
}

#pragma mark - Sweep dispatch — pending / terminal branching

/// Pending sweep entries enroll into the click-time poll loop's tracking
/// dictionary so the existing scheduleNextPoll machinery picks them up. The
/// cross-SDK contract: pending claims surfaced by the sweep continue with the
/// same poll loop the click-time path uses, no parallel implementation.
- (void)testSweepRegistersPendingClaimInInflightDictionary {
  NSDictionary* attribution = @{
    @"teakNotifId" : @"2048153148060669486",
    @"teakRewardId" : @"2048153148060669138",
    @"teakChannelName" : @"ios_push",
  };
  NSArray* claims = @[ @{
    @"event_id" : @"evt-sweep-pending-1",
    @"status" : @"pending",
    @"session_attribution" : attribution,
  } ];

  [TeakClaimPoll dispatchSweptClaims:claims session:nil];
  [self drainMainQueue];

  id slot = [TeakClaimPoll inflightClaims][@"evt-sweep-pending-1"];
  XCTAssertNotNil(slot, @"sweep must enroll the pending claim into the in-flight dictionary");
}

/// Terminal sweep entries also enroll into the in-flight dictionary so the
/// existing /claim_ack retriable machinery (with its bounded retry budget and
/// originating-session pin) handles ack for the resurfaced claim.
- (void)testSweepRegistersTerminalClaimInInflightDictionary {
  NSArray* claims = @[ @{
    @"event_id" : @"evt-sweep-terminal-1",
    @"status" : @"completed",
    @"reward" : @{@"gems" : @25},
    @"customer_status_code" : @200,
    @"session_attribution" : @{@"teakNotifId" : @"2048153148060669486"},
  } ];

  [TeakClaimPoll dispatchSweptClaims:claims session:nil];
  [self drainMainQueue];

  id slot = [TeakClaimPoll inflightClaims][@"evt-sweep-terminal-1"];
  XCTAssertNotNil(slot, @"sweep must enroll the terminal claim so the ack retry path can reach it");
}

#pragma mark - Sweep dispatch — idempotency vs. click-time path

/// A claim that's already in flight from a click-time start MUST NOT be
/// re-entered by the sweep. The dedupe guard is the existing in-flight
/// dictionary keyed on event_id (re-entrant start_poll for the same event_id
/// is a no-op per cross-SDK conventions).
- (void)testSweepSkipsClaimAlreadyInFlightFromClickTime {
  NSString* eventId = @"evt-clicktime-already-1";
  // Long delay so the click-time entry's timer can't fire mid-test.
  [TeakClaimPoll startPollForEventId:eventId launchData:nil initialDelay:60.0 ceiling:120.0];
  [self drainMainQueue];

  id clickTimeSlot = [TeakClaimPoll inflightClaims][eventId];
  XCTAssertNotNil(clickTimeSlot, @"precondition: click-time claim is in flight");

  NSArray* claims = @[ @{
    @"event_id" : eventId,
    @"status" : @"completed",
    @"session_attribution" : @{@"teakNotifId" : @"2048153148060669486"},
  } ];

  [TeakClaimPoll dispatchSweptClaims:claims session:nil];
  [self drainMainQueue];

  id afterSweep = [TeakClaimPoll inflightClaims][eventId];
  XCTAssertEqual(clickTimeSlot, afterSweep,
                 @"sweep must not replace an in-flight click-time claim entry for the same event_id");
  XCTAssertEqual([TeakClaimPoll inflightClaims].count, (NSUInteger)1,
                 @"sweep dedupe must keep the dictionary at one entry for the duplicated event_id");
}

#pragma mark - Sweep dispatch — pending does not re-fire ClaimPending

/// Per cross-SDK conventions: ClaimPending is a point-in-time event, not a
/// history-replay event. The sweep enrolls pending entries into the poll loop
/// without re-firing TeakOnRewardClaimPending. Host games that listened on
/// click-time already saw the optimistic surface; resurfaced pendings just
/// continue polling silently until terminal.
- (void)testSweepDoesNotFireClaimPendingNotification {
  __block BOOL fired = NO;
  id<NSObject> observer = [[NSNotificationCenter defaultCenter]
      addObserverForName:TeakOnRewardClaimPending
                  object:nil
                   queue:nil
              usingBlock:^(NSNotification* note) {
                fired = YES;
              }];

  NSArray* claims = @[ @{
    @"event_id" : @"evt-sweep-pending-silent-1",
    @"status" : @"pending",
    @"session_attribution" : @{@"teakNotifId" : @"2048153148060669486"},
  } ];

  [TeakClaimPoll dispatchSweptClaims:claims session:nil];
  [self drainMainQueue];

  [[NSNotificationCenter defaultCenter] removeObserver:observer];
  XCTAssertFalse(fired, @"sweep must never fire TeakOnRewardClaimPending — Pending is point-in-time only");
}

#pragma mark - Sweep dispatch — input tolerance

/// An empty claims list is a valid response shape (the user has no unacked
/// claims) — sweep dispatcher must handle it without enrolling any entries
/// or crashing.
- (void)testSweepHandlesEmptyClaimsListWithoutCrashing {
  [TeakClaimPoll dispatchSweptClaims:@[] session:nil];
  [self drainMainQueue];

  XCTAssertEqual([TeakClaimPoll inflightClaims].count, (NSUInteger)0);
}

/// A malformed individual claim entry (missing event_id, wrong types) is
/// dropped without taking the rest of the list down. The dispatcher iterates
/// defensively so a single server-side anomaly doesn't strand the user's
/// other unacked claims.
- (void)testSweepSkipsMalformedClaimsAndDispatchesRest {
  NSArray* claims = @[
    @{@"status" : @"completed"},                       // missing event_id
    @{@"event_id" : @"evt-good-1", @"status" : @"pending"},
    @"not-a-dict",                                      // wrong shape entirely
    @{@"event_id" : @"", @"status" : @"completed"},     // empty event_id
  ];

  [TeakClaimPoll dispatchSweptClaims:claims session:nil];
  [self drainMainQueue];

  XCTAssertNotNil([TeakClaimPoll inflightClaims][@"evt-good-1"],
                  @"the well-formed claim must still be enrolled despite malformed siblings");
  XCTAssertEqual([TeakClaimPoll inflightClaims].count, (NSUInteger)1,
                 @"only the well-formed claim should be tracked");
}

#pragma mark - Sweep dispatch — session_attribution unpack tolerance

#pragma mark - Sweep dispatch — clicking_user_id capture

/// Sweep enrollment captures the dispatching session's userId onto each
/// in-flight claim's clicking_user_id slot. Subsequent /claim_status polls
/// and /claim_ack POSTs for the resurfaced claim read from this captured
/// value, not from a live session reference at request-send time. This
/// matches the click-time capture-at-click contract — the user that owned
/// the click owns the per-claim wire identity for that claim's lifetime.
- (void)testSweepCapturesClickingUserIdFromSessionOntoEachClaim {
  TeakSession* mockSession = mock([TeakSession class]);
  [given([mockSession userId]) willReturn:@"user-sweep-A"];

  NSArray* claims = @[
    @{
      @"event_id" : @"evt-sweep-capture-1",
      @"status" : @"pending",
      @"session_attribution" : @{@"teakNotifId" : @"2048153148060669486"},
    },
    @{
      @"event_id" : @"evt-sweep-capture-2",
      @"status" : @"completed",
      @"reward" : @{@"gems" : @25},
    },
  ];

  [TeakClaimPoll dispatchSweptClaims:claims session:mockSession];
  [self drainMainQueue];

  TeakInflightClaim* pendingClaim = [TeakClaimPoll inflightClaims][@"evt-sweep-capture-1"];
  TeakInflightClaim* terminalClaim = [TeakClaimPoll inflightClaims][@"evt-sweep-capture-2"];
  XCTAssertEqualObjects(pendingClaim.clickingUserId, @"user-sweep-A",
                        @"pending sweep entry must capture clicking_user_id from the dispatching session");
  XCTAssertEqualObjects(terminalClaim.clickingUserId, @"user-sweep-A",
                        @"terminal sweep entry must capture clicking_user_id from the dispatching session");
}

/// session_attribution may arrive as a JSON-encoded string (mirrors the
/// click-POST mint shape) or as an inline dict. The sweep dispatcher tolerates
/// both forms so the SDK is robust to either taro-side encoding choice.
- (void)testSweepUnpacksSessionAttributionFromJsonString {
  NSDictionary* attribution = @{
    @"teakNotifId" : @"2048153148060669486",
    @"teakRewardId" : @"2048153148060669138",
  };
  NSData* data = [NSJSONSerialization dataWithJSONObject:attribution options:0 error:nil];
  NSString* attributionString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

  NSArray* claims = @[ @{
    @"event_id" : @"evt-sweep-string-attr-1",
    @"status" : @"pending",
    @"session_attribution" : attributionString,
  } ];

  [TeakClaimPoll dispatchSweptClaims:claims session:nil];
  [self drainMainQueue];

  XCTAssertNotNil([TeakClaimPoll inflightClaims][@"evt-sweep-string-attr-1"],
                  @"sweep must accept session_attribution as a JSON-encoded string");
}

@end
