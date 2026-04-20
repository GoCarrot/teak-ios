#import <XCTest/XCTest.h>

#import <Teak/Teak.h>

#import "TeakLaunchData.h"

@import OCHamcrest;
@import OCMockito;

// Re-expose the private designated initializer so tests can construct
// TeakAttributedLaunchData directly without going through a factory.
@interface TeakAttributedLaunchData (Testing)
- (id)initWithUrl:(NSURL*)url andShortLink:(NSURL*)shortLink;
@end

// Forward-declare TeakConfiguration so +setUp can seed the singleton without
// importing TeakConfiguration.h (its transitive imports aren't on the test
// target's HEADER_SEARCH_PATHS and collide with Teak.h).
@interface TeakConfiguration : NSObject
+ (BOOL)configureForAppId:(NSString*)appId andSecret:(NSString*)appSecret;
@end

@interface TeakAttributedLaunchDataEnrichmentTests : XCTestCase
@end

@implementation TeakAttributedLaunchDataEnrichmentTests

+ (void)setUp {
  [super setUp];
  // to_h calls TeakLink_WillHandleDeepLink → TeakConfiguration.configuration.
  @try {
    [TeakConfiguration configureForAppId:@"test-app" andSecret:@"test-secret"];
  } @catch (NSException* e) {
    // Already initialized — fine.
  }
}

#pragma mark - Bare attributed launch data (no pre-existing attribution)

/// When there's no pre-existing attribution, a later updateDeepLink: with a URL
/// that carries teak_* params must actually populate the attribution fields.
/// Before the initWithUrl:andShortLink: fix, newLaunchData was built via the
/// parent's initWithUrl: (no query parsing), so NewIfNotOld(nil, nil) always
/// returned nil and the enrichment merge was a no-op.
- (void)testUpdateDeepLinkPopulatesAttributionWhenOldIsNil {
  NSURL* bareUrl = [NSURL URLWithString:@"teaktest-app://menu"];
  TeakAttributedLaunchData* data = [[TeakAttributedLaunchData alloc] initWithUrl:bareUrl andShortLink:nil];
  XCTAssertNil(data.scheduleId);
  XCTAssertNil(data.creativeId);
  XCTAssertNil(data.rewardId);

  NSURL* enrichedUrl = [NSURL URLWithString:@"teaktest-app://chest?teak_schedule_id=7&teak_schedule_name=daily&teak_creative_id=42&teak_creative_name=banner&teak_reward_id=99&teak_channel_name=push&teak_opt_out_category=promos"];
  [data updateDeepLink:enrichedUrl];

  XCTAssertEqualObjects(data.scheduleId, @"7");
  XCTAssertEqualObjects(data.scheduleName, @"daily");
  XCTAssertEqualObjects(data.creativeId, @"42");
  XCTAssertEqualObjects(data.creativeName, @"banner");
  XCTAssertEqualObjects(data.rewardId, @"99");
  XCTAssertEqualObjects(data.channelName, @"push");
  XCTAssertEqualObjects(data.optOutCategory, @"promos");
  XCTAssertEqualObjects(data.deepLink, enrichedUrl);
}

/// to_h must surface the enriched fields too, since TeakPostLaunchSummary uses
/// this dict as its userInfo. Previously blocked by the same newLaunchData bug.
- (void)testUpdateDeepLinkEnrichmentFlowsIntoToH {
  NSURL* bareUrl = [NSURL URLWithString:@"teaktest-app://menu"];
  TeakAttributedLaunchData* data = [[TeakAttributedLaunchData alloc] initWithUrl:bareUrl andShortLink:nil];

  NSURL* enrichedUrl = [NSURL URLWithString:@"teaktest-app://chest?teak_schedule_id=7&teak_creative_id=42&teak_reward_id=99"];
  [data updateDeepLink:enrichedUrl];

  NSDictionary* dict = [data to_h];
  XCTAssertEqualObjects(dict[@"teakScheduleId"], @"7");
  XCTAssertEqualObjects(dict[@"teakCreativeId"], @"42");
  XCTAssertEqualObjects(dict[@"teakRewardId"], @"99");
}

#pragma mark - Pre-existing attribution (behavior preservation)

/// When the launch data already has attribution (notification/URL launches),
/// NewIfNotOld keeps old when non-nil — the fix must not change that behavior.
- (void)testUpdateDeepLinkPreservesExistingAttributionWhenOldIsNonNil {
  NSURL* originalUrl = [NSURL URLWithString:@"teaktest-app://chest?teak_schedule_id=ORIGINAL&teak_creative_id=ORIGINAL_CREATIVE&teak_reward_id=ORIGINAL_REWARD"];
  TeakAttributedLaunchData* data = [[TeakAttributedLaunchData alloc] initWithUrl:originalUrl andShortLink:nil];
  XCTAssertEqualObjects(data.scheduleId, @"ORIGINAL");

  NSURL* enrichedUrl = [NSURL URLWithString:@"teaktest-app://chest?teak_schedule_id=ENRICHED&teak_creative_id=ENRICHED_CREATIVE&teak_reward_id=ENRICHED_REWARD"];
  [data updateDeepLink:enrichedUrl];

  XCTAssertEqualObjects(data.scheduleId, @"ORIGINAL", @"old non-nil attribution must win over enriched URL values");
  XCTAssertEqualObjects(data.creativeId, @"ORIGINAL_CREATIVE");
  XCTAssertEqualObjects(data.rewardId, @"ORIGINAL_REWARD");
  XCTAssertEqualObjects(data.deepLink, enrichedUrl, @"deepLink itself should still update");
}

/// A mix: old has some slots, new fills in the rest.
- (void)testUpdateDeepLinkFillsMissingSlotsWithoutOverridingOld {
  NSURL* originalUrl = [NSURL URLWithString:@"teaktest-app://chest?teak_schedule_id=ORIGINAL_SCHEDULE"];
  TeakAttributedLaunchData* data = [[TeakAttributedLaunchData alloc] initWithUrl:originalUrl andShortLink:nil];
  XCTAssertEqualObjects(data.scheduleId, @"ORIGINAL_SCHEDULE");
  XCTAssertNil(data.creativeId);

  NSURL* enrichedUrl = [NSURL URLWithString:@"teaktest-app://chest?teak_schedule_id=ENRICHED_SCHEDULE&teak_creative_id=NEW_CREATIVE"];
  [data updateDeepLink:enrichedUrl];

  XCTAssertEqualObjects(data.scheduleId, @"ORIGINAL_SCHEDULE", @"slot with old value preserves it");
  XCTAssertEqualObjects(data.creativeId, @"NEW_CREATIVE", @"slot that was nil gets filled by enriched URL");
}

@end
