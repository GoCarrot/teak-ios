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

/// When there's no pre-existing attribution, updatedWithDeepLink: with a URL that
/// carries teak_* params must populate the attribution fields on the RETURNED
/// object, and must leave the receiver untouched — the receiver may already be
/// published/read from another queue by the time this runs.
- (void)testUpdateDeepLinkPopulatesAttributionWhenOldIsNil {
  NSURL* bareUrl = [NSURL URLWithString:@"teaktest-app://menu"];
  TeakAttributedLaunchData* data = [[TeakAttributedLaunchData alloc] initWithUrl:bareUrl andShortLink:nil];
  XCTAssertNil(data.scheduleId);
  XCTAssertNil(data.creativeId);
  XCTAssertNil(data.rewardId);

  NSURL* enrichedUrl = [NSURL URLWithString:@"teaktest-app://chest?teak_schedule_id=7&teak_schedule_name=daily&teak_creative_id=42&teak_creative_name=banner&teak_reward_id=99&teak_channel_name=push&teak_opt_out_category=promos"];
  TeakAttributedLaunchData* updated = (TeakAttributedLaunchData*)[data updatedWithDeepLink:enrichedUrl];

  XCTAssertTrue(updated != data, @"updatedWithDeepLink: must return a fresh object, not mutate the receiver");
  XCTAssertEqualObjects(updated.scheduleId, @"7");
  XCTAssertEqualObjects(updated.scheduleName, @"daily");
  XCTAssertEqualObjects(updated.creativeId, @"42");
  XCTAssertEqualObjects(updated.creativeName, @"banner");
  XCTAssertEqualObjects(updated.rewardId, @"99");
  XCTAssertEqualObjects(updated.channelName, @"push");
  XCTAssertEqualObjects(updated.optOutCategory, @"promos");
  XCTAssertEqualObjects(updated.deepLink, enrichedUrl);

  // Regression guard: the receiver must remain exactly as constructed.
  XCTAssertNil(data.scheduleId);
  XCTAssertNil(data.creativeId);
  XCTAssertNil(data.rewardId);
  XCTAssertNil(data.channelName);
  XCTAssertNil(data.optOutCategory);
  XCTAssertEqualObjects(data.deepLink, bareUrl);
}

/// to_h must surface the enriched fields too, since TeakPostLaunchSummary uses
/// this dict as its userInfo — read off the returned object, not the receiver.
- (void)testUpdateDeepLinkEnrichmentFlowsIntoToH {
  NSURL* bareUrl = [NSURL URLWithString:@"teaktest-app://menu"];
  TeakAttributedLaunchData* data = [[TeakAttributedLaunchData alloc] initWithUrl:bareUrl andShortLink:nil];

  NSURL* enrichedUrl = [NSURL URLWithString:@"teaktest-app://chest?teak_schedule_id=7&teak_creative_id=42&teak_reward_id=99"];
  TeakAttributedLaunchData* updated = (TeakAttributedLaunchData*)[data updatedWithDeepLink:enrichedUrl];

  NSDictionary* dict = [updated to_h];
  XCTAssertEqualObjects(dict[@"teakScheduleId"], @"7");
  XCTAssertEqualObjects(dict[@"teakCreativeId"], @"42");
  XCTAssertEqualObjects(dict[@"teakRewardId"], @"99");

  // The receiver's own to_h must be unaffected by the enrichment.
  NSDictionary* originalDict = [data to_h];
  XCTAssertEqualObjects(originalDict[@"teakScheduleId"], [NSNull null]);
  XCTAssertEqualObjects(originalDict[@"teakCreativeId"], [NSNull null]);
  XCTAssertEqualObjects(originalDict[@"teakRewardId"], [NSNull null]);
}

#pragma mark - Pre-existing attribution (behavior preservation)

/// When the launch data already has attribution (notification/URL launches),
/// NewIfNotOld keeps old when non-nil — the fix must not change that behavior.
- (void)testUpdateDeepLinkPreservesExistingAttributionWhenOldIsNonNil {
  NSURL* originalUrl = [NSURL URLWithString:@"teaktest-app://chest?teak_schedule_id=ORIGINAL&teak_creative_id=ORIGINAL_CREATIVE&teak_reward_id=ORIGINAL_REWARD"];
  TeakAttributedLaunchData* data = [[TeakAttributedLaunchData alloc] initWithUrl:originalUrl andShortLink:nil];
  XCTAssertEqualObjects(data.scheduleId, @"ORIGINAL");

  NSURL* enrichedUrl = [NSURL URLWithString:@"teaktest-app://chest?teak_schedule_id=ENRICHED&teak_creative_id=ENRICHED_CREATIVE&teak_reward_id=ENRICHED_REWARD"];
  TeakAttributedLaunchData* updated = (TeakAttributedLaunchData*)[data updatedWithDeepLink:enrichedUrl];

  XCTAssertEqualObjects(updated.scheduleId, @"ORIGINAL", @"old non-nil attribution must win over enriched URL values");
  XCTAssertEqualObjects(updated.creativeId, @"ORIGINAL_CREATIVE");
  XCTAssertEqualObjects(updated.rewardId, @"ORIGINAL_REWARD");
  XCTAssertEqualObjects(updated.deepLink, enrichedUrl, @"deepLink itself should still update");

  // The receiver's own deepLink must not have changed.
  XCTAssertEqualObjects(data.deepLink, originalUrl);
  XCTAssertEqualObjects(data.scheduleId, @"ORIGINAL");
}

/// A mix: old has some slots, new fills in the rest.
- (void)testUpdateDeepLinkFillsMissingSlotsWithoutOverridingOld {
  NSURL* originalUrl = [NSURL URLWithString:@"teaktest-app://chest?teak_schedule_id=ORIGINAL_SCHEDULE"];
  TeakAttributedLaunchData* data = [[TeakAttributedLaunchData alloc] initWithUrl:originalUrl andShortLink:nil];
  XCTAssertEqualObjects(data.scheduleId, @"ORIGINAL_SCHEDULE");
  XCTAssertNil(data.creativeId);

  NSURL* enrichedUrl = [NSURL URLWithString:@"teaktest-app://chest?teak_schedule_id=ENRICHED_SCHEDULE&teak_creative_id=NEW_CREATIVE"];
  TeakAttributedLaunchData* updated = (TeakAttributedLaunchData*)[data updatedWithDeepLink:enrichedUrl];

  XCTAssertEqualObjects(updated.scheduleId, @"ORIGINAL_SCHEDULE", @"slot with old value preserves it");
  XCTAssertEqualObjects(updated.creativeId, @"NEW_CREATIVE", @"slot that was nil gets filled by enriched URL");

  // The receiver never gets the new creativeId — it was never mutated.
  XCTAssertNil(data.creativeId);
}

@end
