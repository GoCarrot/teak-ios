#import <XCTest/XCTest.h>

#import <Teak/Teak.h>

#import "TeakLaunchData.h"

@import OCHamcrest;
@import OCMockito;

// Re-expose internal initializer for testing.
@interface TeakLiveActivityLaunchData (Testing)
- (id)initWithSystemActivityId:(NSString*)systemActivityId;
@end

// Forward-declare TeakConfiguration's init selector so +setUp can seed the
// singleton without importing TeakConfiguration.h (its transitive imports
// aren't on the test target's HEADER_SEARCH_PATHS and collide with Teak.h).
@interface TeakConfiguration : NSObject
+ (BOOL)configureForAppId:(NSString*)appId andSecret:(NSString*)appSecret;
@end

@interface TeakLiveActivityLaunchDataTests : XCTestCase
@end

@implementation TeakLiveActivityLaunchDataTests

static NSString* const kSystemActivityId = @"D3CBB9AF-7292-4FD9-B22D-DEAC3D033BD2";

+ (void)setUp {
  [super setUp];
  // to_h walks up to TeakAttributedLaunchData.to_h which calls
  // TeakLink_WillHandleDeepLink → TeakConfiguration.configuration. Ensure the
  // singleton exists so tests exercise the production to_h path. Guarded so
  // repeat runs and other test classes that may also init don't double-init.
  @try {
    [TeakConfiguration configureForAppId:@"test-app" andSecret:@"test-secret"];
  } @catch (NSException* e) {
    // Already initialized — fine.
  }
}

#pragma mark - Class shape

- (void)testInheritsFromTeakAttributedLaunchData {
  TeakLiveActivityLaunchData* data = [[TeakLiveActivityLaunchData alloc] initWithSystemActivityId:kSystemActivityId];
  XCTAssertTrue([data isKindOfClass:[TeakAttributedLaunchData class]]);
}

- (void)testInitPopulatesSystemActivityId {
  TeakLiveActivityLaunchData* data = [[TeakLiveActivityLaunchData alloc] initWithSystemActivityId:kSystemActivityId];
  XCTAssertEqualObjects(data.systemActivityId, kSystemActivityId);
}

#pragma mark - sessionAttribution

- (void)testSessionAttributionContainsTeakLiveActivityId {
  TeakLiveActivityLaunchData* data = [[TeakLiveActivityLaunchData alloc] initWithSystemActivityId:kSystemActivityId];
  NSDictionary* attribution = [data sessionAttribution];
  XCTAssertEqualObjects(attribution[@"teak_live_activity_id"], kSystemActivityId);
}

- (void)testSessionAttributionDoesNotOverrideWithNotifId {
  TeakLiveActivityLaunchData* data = [[TeakLiveActivityLaunchData alloc] initWithSystemActivityId:kSystemActivityId];
  NSDictionary* attribution = [data sessionAttribution];
  XCTAssertNil(attribution[@"teak_notif_id"]);
}

#pragma mark - to_h

- (void)testToHContainsSystemActivityId {
  TeakLiveActivityLaunchData* data = [[TeakLiveActivityLaunchData alloc] initWithSystemActivityId:kSystemActivityId];
  NSDictionary* dict = [data to_h];
  XCTAssertEqualObjects(dict[@"teakSystemActivityId"], kSystemActivityId);
}

#pragma mark - TeakLaunchDataOperation factory

- (void)testFromLiveActivityTapProducesLiveActivityLaunchData {
  TeakLaunchDataOperation* op = [TeakLaunchDataOperation fromLiveActivityTap:kSystemActivityId];

  NSOperationQueue* queue = [[NSOperationQueue alloc] init];
  [queue addOperation:op];
  [queue waitUntilAllOperationsAreFinished];

  XCTAssertTrue([op.result isKindOfClass:[TeakLiveActivityLaunchData class]]);
  TeakLiveActivityLaunchData* data = (TeakLiveActivityLaunchData*)op.result;
  XCTAssertEqualObjects(data.systemActivityId, kSystemActivityId);
}

- (void)testFromLiveActivityTapResultSessionAttributionHasTeakLiveActivityId {
  TeakLaunchDataOperation* op = [TeakLaunchDataOperation fromLiveActivityTap:kSystemActivityId];

  NSOperationQueue* queue = [[NSOperationQueue alloc] init];
  [queue addOperation:op];
  [queue waitUntilAllOperationsAreFinished];

  NSDictionary* attribution = [op.result sessionAttribution];
  XCTAssertEqualObjects(attribution[@"teak_live_activity_id"], kSystemActivityId);
}

#pragma mark - NSUserActivity dispatch (simulated activity-resumption callback)

/// Build an NSUserActivity mimicking what iOS delivers when the user taps a Live Activity.
/// activityType = "NSUserActivityTypeLiveActivity"; userInfo["WGWidgetUserInfoKeyActivityID"] = Activity.id.
- (NSUserActivity*)liveActivityUserActivityWithId:(NSString*)activityId {
  NSUserActivity* activity = [[NSUserActivity alloc] initWithActivityType:@"NSUserActivityTypeLiveActivity"];
  activity.userInfo = @{@"WGWidgetUserInfoKeyActivityID" : activityId};
  return activity;
}

- (void)testFromUserActivityRecognizesLiveActivityTap {
  NSUserActivity* userActivity = [self liveActivityUserActivityWithId:kSystemActivityId];
  TeakLaunchDataOperation* op = [TeakLaunchDataOperation fromUserActivity:userActivity];
  XCTAssertNotNil(op);

  NSOperationQueue* queue = [[NSOperationQueue alloc] init];
  [queue addOperation:op];
  [queue waitUntilAllOperationsAreFinished];

  XCTAssertTrue([op.result isKindOfClass:[TeakLiveActivityLaunchData class]]);
  TeakLiveActivityLaunchData* data = (TeakLiveActivityLaunchData*)op.result;
  XCTAssertEqualObjects(data.systemActivityId, kSystemActivityId);
}

- (void)testFromUserActivityIgnoresLiveActivityTapWithoutSystemActivityId {
  NSUserActivity* activity = [[NSUserActivity alloc] initWithActivityType:@"NSUserActivityTypeLiveActivity"];
  activity.userInfo = @{};
  XCTAssertNil([TeakLaunchDataOperation fromUserActivity:activity]);
}

- (void)testFromUserActivityIgnoresLiveActivityTapWithEmptySystemActivityId {
  NSUserActivity* activity = [[NSUserActivity alloc] initWithActivityType:@"NSUserActivityTypeLiveActivity"];
  activity.userInfo = @{@"WGWidgetUserInfoKeyActivityID" : @""};
  XCTAssertNil([TeakLaunchDataOperation fromUserActivity:activity]);
}

- (void)testFromUserActivityIgnoresUnknownActivityType {
  NSUserActivity* activity = [[NSUserActivity alloc] initWithActivityType:@"com.example.unknown"];
  XCTAssertNil([TeakLaunchDataOperation fromUserActivity:activity]);
}

- (void)testFromUserActivityReturnsNilForNilUserActivity {
  XCTAssertNil([TeakLaunchDataOperation fromUserActivity:nil]);
}

#pragma mark - Server-side attribution enrichment (updateDeepLink)

/// Simulates the users.json reply path: server responds with a `deep_link` carrying
/// teak_* query params, TeakSession calls updateDeepLink:withLaunchLink: on our
/// launch data operation, and the enriched fields surface in both sessionAttribution
/// (already-identified sessions) and to_h (TeakPostLaunchSummary userInfo).
- (void)testUpdateDeepLinkEnrichesAttributedFieldsAndPreservesSystemActivityId {
  TeakLaunchDataOperation* op = [TeakLaunchDataOperation fromLiveActivityTap:kSystemActivityId];
  NSOperationQueue* queue = [[NSOperationQueue alloc] init];
  [queue addOperation:op];
  [queue waitUntilAllOperationsAreFinished];

  NSURL* enrichedDeepLink = [NSURL URLWithString:@"teaktest-app://chest?teak_schedule_id=7&teak_creative_id=42&teak_reward_id=99"];
  [op updateDeepLink:enrichedDeepLink withLaunchLink:nil];

  TeakLiveActivityLaunchData* data = (TeakLiveActivityLaunchData*)op.result;
  XCTAssertEqualObjects(data.systemActivityId, kSystemActivityId, @"updateDeepLink: must not clobber systemActivityId");

  NSDictionary* attribution = [data sessionAttribution];
  XCTAssertEqualObjects(attribution[@"teak_live_activity_id"], kSystemActivityId);
  XCTAssertEqualObjects(attribution[@"teak_schedule_id"], @"7");
  XCTAssertEqualObjects(attribution[@"teak_creative_id"], @"42");
  XCTAssertEqualObjects(attribution[@"teak_reward_id"], @"99");

  NSDictionary* dict = [data to_h];
  XCTAssertEqualObjects(dict[@"teakSystemActivityId"], kSystemActivityId);
  XCTAssertEqualObjects(dict[@"teakScheduleId"], @"7");
  XCTAssertEqualObjects(dict[@"teakCreativeId"], @"42");
  XCTAssertEqualObjects(dict[@"teakRewardId"], @"99");
}

- (void)testFromUserActivityHandlesBrowsingWeb {
  NSUserActivity* activity = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
  activity.webpageURL = [NSURL URLWithString:@"https://example.com/foo"];
  TeakLaunchDataOperation* op = [TeakLaunchDataOperation fromUserActivity:activity];
  XCTAssertNotNil(op, @"Browsing-web activities should still produce a launch data operation");
}

@end
