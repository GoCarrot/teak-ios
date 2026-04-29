#import <XCTest/XCTest.h>

#import <Teak/Teak.h>

#import "TeakClaimPoll.h"
#import "TeakLaunchData.h"
#import "TeakSession.h"

@import OCHamcrest;
@import OCMockito;

// Internal dispatcher under test. Lives on TeakSession; the SDK branches the
// click-time wire response on its `status` field and constructs an
// NSNotification with a payload shape derived from the launch data + reply.
// The notification is returned (and posted) so tests can inspect both name
// and userInfo without needing to wire NSNotificationCenter observers.
@interface TeakSession (Testing)
+ (NSNotification*)dispatchClickResponse:(NSDictionary*)reply
                           forLaunchData:(TeakAttributedLaunchData*)launchData;
@end

@interface TeakNotificationLaunchData (Testing)
- (id)initWithUrl:(NSURL*)url;
@end

@interface TeakRewardlinkLaunchData (Testing)
- (id)initWithUrl:(NSURL*)url andShortLink:(NSURL*)shortLink;
@end

@interface TeakConfiguration : NSObject
+ (BOOL)configureForAppId:(NSString*)appId andSecret:(NSString*)appSecret;
@end

@interface JwtModeRewardEventsTests : XCTestCase
@end

@implementation JwtModeRewardEventsTests

+ (void)setUp {
  [super setUp];
  @try {
    [TeakConfiguration configureForAppId:@"test-app" andSecret:@"test-secret"];
  } @catch (NSException* e) {
    // Already initialized — fine.
  }
}

- (void)tearDown {
  // dispatchClickResponse:forLaunchData: starts a real poll on claim_pending.
  // Cancel any scheduled timers between test cases so they don't leak.
  [TeakClaimPoll cancelAllPolls];
  [super tearDown];
}

#pragma mark - Notification name surface

/// The three new wire events are NSNotification names exported alongside
/// TeakOnReward. Keep them as plain string constants so host games can listen
/// without importing internal headers.
- (void)testJwtModeNotificationNamesAreExported {
  XCTAssertEqualObjects(TeakOnRewardJwtIssued, @"TeakOnRewardJwtIssued");
  XCTAssertEqualObjects(TeakOnRewardClaimPending, @"TeakOnRewardClaimPending");
  XCTAssertEqualObjects(TeakOnRewardClaimResolved, @"TeakOnRewardClaimResolved");
}

#pragma mark - dispatchClickResponse:forLaunchData: branches on status

- (TeakAttributedLaunchData*)launchDataForNotificationFixture {
  // Notification-fixture-shaped URL: the resulting to_h round-trips the
  // canonical eleven keys with the notification slots populated.
  NSURL* url = [NSURL URLWithString:@"teaktest-app://chest?teak_notif_id=2048153148060669486&teak_schedule_id=2046986133304291328&teak_schedule_name=daily_promo_2026q2&teak_creative_id=2046986561123301779&teak_creative_name=summer_sale_v3&teak_reward_id=2048153148060669138&teak_channel_name=ios_push&teak_opt_out_category=teak"];
  return [[TeakNotificationLaunchData alloc] initWithUrl:url];
}

/// Wire `status: 'grant_reward'` goes to the existing TeakOnReward event
/// (legacy path — preserved for back-compat with non-JWT apps).
- (void)testGrantRewardStatusFiresLegacyTeakOnReward {
  NSDictionary* reply = @{
    @"status" : @"grant_reward",
    @"reward" : @{@"coins" : @100},
    @"teakRewardId" : @"2048153148060669138",
  };
  TeakAttributedLaunchData* launchData = [self launchDataForNotificationFixture];

  NSNotification* note = [TeakSession dispatchClickResponse:reply forLaunchData:launchData];
  XCTAssertEqualObjects(note.name, TeakOnReward);
  XCTAssertEqualObjects(note.userInfo[@"status"], @"grant_reward");
  XCTAssertEqualObjects(note.userInfo[@"teakNotifId"], @"2048153148060669486");
}

/// Wire `status: 'token_issued'` (client_jwt mode) fires TeakOnRewardJwtIssued.
/// Payload includes the JWT token, event_id, reward, claim_source, teak_reward_id,
/// merged with the launchData.to_h so host games get the full provenance.
- (void)testTokenIssuedStatusFiresJwtIssuedEvent {
  NSDictionary* reply = @{
    @"status" : @"token_issued",
    @"token" : @"eyJ.fake.jwt",
    @"event_id" : @"evt-2048153148060669500",
    @"reward" : @{@"coins" : @100},
    @"claim_source" : @"server",
    @"teak_reward_id" : @"2048153148060669138",
  };
  TeakAttributedLaunchData* launchData = [self launchDataForNotificationFixture];

  NSNotification* note = [TeakSession dispatchClickResponse:reply forLaunchData:launchData];
  XCTAssertEqualObjects(note.name, TeakOnRewardJwtIssued);

  XCTAssertEqualObjects(note.userInfo[@"status"], @"token_issued");
  XCTAssertEqualObjects(note.userInfo[@"token"], @"eyJ.fake.jwt");
  XCTAssertEqualObjects(note.userInfo[@"event_id"], @"evt-2048153148060669500");
  XCTAssertEqualObjects(note.userInfo[@"reward"], @{@"coins" : @100});
  XCTAssertEqualObjects(note.userInfo[@"claim_source"], @"server");
  XCTAssertEqualObjects(note.userInfo[@"teak_reward_id"], @"2048153148060669138");

  // Provenance from launchData.to_h must ride along on JWT-issued events.
  XCTAssertEqualObjects(note.userInfo[@"teakNotifId"], @"2048153148060669486");
  XCTAssertEqualObjects(note.userInfo[@"teakScheduleId"], @"2046986133304291328");
  XCTAssertEqualObjects(note.userInfo[@"teakCreativeId"], @"2046986561123301779");
}

/// Wire `status: 'claim_pending'` (server_jwt mode) fires TeakOnRewardClaimPending.
/// Payload carries the event_id the SDK polls /claim_status against, plus the
/// JWT/reward/etc. so the host game can show optimistic UI while polling runs.
- (void)testClaimPendingStatusFiresClaimPendingEvent {
  NSDictionary* reply = @{
    @"status" : @"claim_pending",
    @"token" : @"eyJ.fake.jwt",
    @"event_id" : @"evt-pending-1",
    @"reward" : @{@"gems" : @25},
    @"claim_source" : @"server",
    @"teak_reward_id" : @"2048153148060669138",
  };
  TeakAttributedLaunchData* launchData = [self launchDataForNotificationFixture];

  NSNotification* note = [TeakSession dispatchClickResponse:reply forLaunchData:launchData];
  XCTAssertEqualObjects(note.name, TeakOnRewardClaimPending);

  XCTAssertEqualObjects(note.userInfo[@"status"], @"claim_pending");
  XCTAssertEqualObjects(note.userInfo[@"event_id"], @"evt-pending-1");
  XCTAssertEqualObjects(note.userInfo[@"token"], @"eyJ.fake.jwt");

  // Provenance still rides on claim_pending so a host game can render the
  // optimistic surface with correct attribution context.
  XCTAssertEqualObjects(note.userInfo[@"teakNotifId"], @"2048153148060669486");
}

/// The gate-rejection statuses (claim_mode_unsupported, invalid_claim_mode)
/// continue to ride the existing TeakOnReward event — no new event for them
/// per spec.
- (void)testClaimModeUnsupportedStatusFiresTeakOnReward {
  NSDictionary* reply = @{
    @"status" : @"claim_mode_unsupported",
  };
  TeakAttributedLaunchData* launchData = [self launchDataForNotificationFixture];

  NSNotification* note = [TeakSession dispatchClickResponse:reply forLaunchData:launchData];
  XCTAssertEqualObjects(note.name, TeakOnReward);
  XCTAssertEqualObjects(note.userInfo[@"status"], @"claim_mode_unsupported");
}

/// An unknown wire status defaults to TeakOnReward (forward compatibility:
/// future enum values render as legacy events host games already handle).
- (void)testUnknownStatusFallsBackToTeakOnReward {
  NSDictionary* reply = @{
    @"status" : @"some_future_status",
  };
  TeakAttributedLaunchData* launchData = [self launchDataForNotificationFixture];

  NSNotification* note = [TeakSession dispatchClickResponse:reply forLaunchData:launchData];
  XCTAssertEqualObjects(note.name, TeakOnReward);
}

#pragma mark - TeakOnRewardClaimResolved payload assembly

/// The resolved-claim event fires when the click-time poll observes a terminal
/// status from /claim_status. userInfo merges the polled status, customer
/// response data, plus the launchData.to_h provenance fields (in-session
/// optimization: SDK uses its own launch-data state instead of round-tripping
/// the persisted blob).
///
/// Reward id surfacing matches the legacy `TeakOnReward` semantics: only the
/// attribution id (`teakRewardId` from launch-data) lands on the userInfo.
/// The wire reply's `teak_reward_id` is stripped — the `reward` blob carries
/// grant content and is what host games render against. The fixture sets a
/// distinct wire id to lock in the strip behavior.
- (void)testResolvedEventCarriesLaunchDataProvenanceAndPollReply {
  NSDictionary* claimStatusReply = @{
    @"event_id" : @"evt-pending-1",
    @"status" : @"completed",
    @"reward" : @{@"gems" : @25},
    @"customer_response" : @"{\"ok\":true}",
    @"customer_status_code" : @200,
    @"acked_at" : [NSNull null],
    @"teak_reward_id" : @"2048153148060669999",
  };
  TeakAttributedLaunchData* launchData = [self launchDataForNotificationFixture];

  NSDictionary* userInfo = [TeakClaimPoll buildResolvedUserInfoForReply:claimStatusReply
                                                          withLaunchData:launchData];

  XCTAssertNotNil(userInfo);
  XCTAssertEqualObjects(userInfo[@"event_id"], @"evt-pending-1");
  XCTAssertEqualObjects(userInfo[@"status"], @"completed");
  XCTAssertEqualObjects(userInfo[@"reward"], @{@"gems" : @25});
  XCTAssertEqualObjects(userInfo[@"customer_response"], @"{\"ok\":true}");
  XCTAssertEqualObjects(userInfo[@"customer_status_code"], @200);

  // Launch-data provenance is carried via the in-session optimization.
  XCTAssertEqualObjects(userInfo[@"teakNotifId"], @"2048153148060669486");
  XCTAssertEqualObjects(userInfo[@"teakScheduleId"], @"2046986133304291328");
  XCTAssertEqualObjects(userInfo[@"teakCreativeId"], @"2046986561123301779");
  XCTAssertEqualObjects(userInfo[@"teakChannelName"], @"ios_push");

  // Only the attribution id surfaces, matching legacy TeakOnReward semantics.
  // The wire's authoritative-grant id is stripped from the resolved-event
  // userInfo; host games inspect the `reward` blob for grant content.
  XCTAssertEqualObjects(userInfo[@"teakRewardId"], @"2048153148060669138");
  XCTAssertNil(userInfo[@"teak_reward_id"]);
}

/// Canonical resolved-event strip set on the /claim_status (click-time-poll)
/// fixture: the redundant wire fields (`teak_reward_id` — superseded by
/// attribution `teakRewardId`; `session_attribution` — already unpacked into
/// discrete top-level keys) are stripped; `acked_at` rides through. The
/// /claim_status reply does not emit `created_at` / `completed_at` today —
/// those fields live on /claims (sweep) and are exercised in the sweep-path
/// timing test in SessionStartSweepTests.m.
- (void)testResolvedEventStripsRedundantWireFieldsOnClaimStatusReply {
  NSDictionary* claimStatusReply = @{
    @"event_id" : @"evt-pending-strip-1",
    @"status" : @"completed",
    @"reward" : @{@"gems" : @25},
    @"acked_at" : @"2026-04-28T17:00:06Z",
    @"teak_reward_id" : @"2048153148060669999",
    @"session_attribution" : @{@"teakNotifId" : @"would-leak-as-raw-blob"},
  };
  TeakAttributedLaunchData* launchData = [self launchDataForNotificationFixture];

  NSDictionary* userInfo = [TeakClaimPoll buildResolvedUserInfoForReply:claimStatusReply
                                                          withLaunchData:launchData];

  XCTAssertEqualObjects(userInfo[@"event_id"], @"evt-pending-strip-1");
  XCTAssertEqualObjects(userInfo[@"status"], @"completed");

  // Redundant wire fields stripped.
  XCTAssertNil(userInfo[@"teak_reward_id"]);
  XCTAssertNil(userInfo[@"session_attribution"]);

  // acked_at rides through — present on /claim_status reply (Surface 2).
  XCTAssertEqualObjects(userInfo[@"acked_at"], @"2026-04-28T17:00:06Z");

  // The launch-data attribution keys still ride along (in-session
  // optimization populates them from the host's own state).
  XCTAssertEqualObjects(userInfo[@"teakNotifId"], @"2048153148060669486");
}

/// When the launch data is nil (defensive — shouldn't happen in production
/// but proves the helper degrades gracefully), the userInfo carries only the
/// poll reply fields.
- (void)testResolvedEventHandlesNilLaunchDataDefensively {
  NSDictionary* claimStatusReply = @{
    @"event_id" : @"evt-pending-1",
    @"status" : @"completed",
  };

  NSDictionary* userInfo = [TeakClaimPoll buildResolvedUserInfoForReply:claimStatusReply
                                                          withLaunchData:nil];

  XCTAssertNotNil(userInfo);
  XCTAssertEqualObjects(userInfo[@"event_id"], @"evt-pending-1");
  XCTAssertEqualObjects(userInfo[@"status"], @"completed");
  XCTAssertNil(userInfo[@"teakNotifId"]);
}

@end
