#import <XCTest/XCTest.h>

#import <Teak/Teak.h>

#import "TeakLaunchData.h"

@import OCHamcrest;
@import OCMockito;

// Re-expose the private designated initializers so tests can construct each
// concrete launch-data subclass without going through factories or the
// notification-payload path.
@interface TeakLaunchData (Testing)
- (id)init;
- (id)initWithUrl:(NSURL*)url;
@end

@interface TeakAttributedLaunchData (Testing)
- (id)initWithUrl:(NSURL*)url andShortLink:(NSURL*)shortLink;
@end

@interface TeakNotificationLaunchData (Testing)
- (id)initWithUrl:(NSURL*)url;
@end

@interface TeakRewardlinkLaunchData (Testing)
- (id)initWithUrl:(NSURL*)url andShortLink:(NSURL*)shortLink;
@end

@interface TeakLiveActivityLaunchData (Testing)
- (id)initWithSystemActivityId:(NSString*)systemActivityId;
@end

// Forward-declare TeakConfiguration's init selector so +setUp can seed the
// singleton without importing TeakConfiguration.h (its transitive imports
// aren't on the test target's HEADER_SEARCH_PATHS and collide with Teak.h).
@interface TeakConfiguration : NSObject
+ (BOOL)configureForAppId:(NSString*)appId andSecret:(NSString*)appSecret;
@end

// The eleven canonical wire keys from session_attribution_spec.md. Every blob
// emitted by every SDK MUST contain exactly this key set, with values either
// strings or NSNull.
static NSArray<NSString*>* TeakCanonicalWireKeys(void) {
  return @[
    @"launch_link",
    @"teakScheduleName",
    @"teakScheduleId",
    @"teakCreativeName",
    @"teakCreativeId",
    @"teakRewardId",
    @"teakChannelName",
    @"teakDeepLink",
    @"teakOptOutCategory",
    @"teakNotifId",
    @"teakSystemActivityId",
  ];
}

@interface SessionAttributionSpecParityTests : XCTestCase
@end

@implementation SessionAttributionSpecParityTests

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

#pragma mark - Helpers

/// Asserts the dictionary has exactly the eleven canonical wire keys present.
/// Fails if any key is missing OR if any extra non-canonical key is present.
- (void)assertCanonicalKeysAlwaysPresent:(NSDictionary*)dict label:(NSString*)label {
  NSArray<NSString*>* canonical = TeakCanonicalWireKeys();
  for (NSString* key in canonical) {
    XCTAssertNotNil(dict[key], @"%@: canonical key '%@' must be present (NSNull or value)", label, key);
  }
  XCTAssertEqual(dict.count, canonical.count,
                 @"%@: to_h must emit exactly %lu keys, got %lu (keys=%@)",
                 label, (unsigned long)canonical.count, (unsigned long)dict.count, dict.allKeys);
}

#pragma mark - All eleven canonical keys always present

/// Bare unattributed launch — only `launch_link` carries a value. The other
/// ten keys must still be present in to_h, all as NSNull. The cross-SDK
/// contract is "every blob carries every key"; readers can address each
/// slot by name without per-launch-class branching.
- (void)testBareLaunchDataEmitsAllElevenKeysWithNullsForUnattributed {
  TeakLaunchData* data = [[TeakLaunchData alloc] init];
  NSDictionary* dict = [data to_h];

  [self assertCanonicalKeysAlwaysPresent:dict label:@"unattributed bare LaunchData"];

  // Every key is null on a bare launch (no URL was supplied).
  for (NSString* key in TeakCanonicalWireKeys()) {
    XCTAssertEqualObjects(dict[key], [NSNull null],
                          @"unattributed: %@ should be NSNull, got %@", key, dict[key]);
  }
}

/// Rewardlink-shaped launch — populates schedule/creative/reward/channel/etc.
/// but not `teakNotifId` or `teakSystemActivityId`. Both must still be present
/// (as NSNull) in to_h.
- (void)testRewardlinkLaunchDataEmitsAllElevenKeys {
  NSURL* url = [NSURL URLWithString:@"teaktest-app://promo?teak_rewardlink_id=42&teak_rewardlink_name=referral&teak_reward_id=99&teak_channel_name=generic_link&teak_opt_out_category=promos"];
  TeakRewardlinkLaunchData* data = [[TeakRewardlinkLaunchData alloc] initWithUrl:url andShortLink:nil];
  NSDictionary* dict = [data to_h];

  [self assertCanonicalKeysAlwaysPresent:dict label:@"rewardlink"];

  // Populated fields
  XCTAssertEqualObjects(dict[@"teakCreativeId"], @"42");
  XCTAssertEqualObjects(dict[@"teakCreativeName"], @"referral");
  XCTAssertEqualObjects(dict[@"teakRewardId"], @"99");
  XCTAssertEqualObjects(dict[@"teakChannelName"], @"generic_link");

  // Class-aware keys are present-but-null on a rewardlink mint.
  XCTAssertEqualObjects(dict[@"teakNotifId"], [NSNull null]);
  XCTAssertEqualObjects(dict[@"teakSystemActivityId"], [NSNull null]);
}

/// Notification launch carries `teakNotifId` but never `teakSystemActivityId`.
/// The latter must still be in to_h as NSNull.
- (void)testNotificationLaunchDataEmitsAllElevenKeys {
  NSURL* url = [NSURL URLWithString:@"teaktest-app://chest?teak_notif_id=12345&teak_schedule_id=7&teak_creative_id=42&teak_reward_id=99&teak_channel_name=ios_push&teak_opt_out_category=promos"];
  TeakNotificationLaunchData* data = [[TeakNotificationLaunchData alloc] initWithUrl:url];
  NSDictionary* dict = [data to_h];

  [self assertCanonicalKeysAlwaysPresent:dict label:@"notification"];

  XCTAssertEqualObjects(dict[@"teakNotifId"], @"12345");
  XCTAssertEqualObjects(dict[@"teakSystemActivityId"], [NSNull null],
                        @"notification mint never populates teakSystemActivityId; must be NSNull, not absent");
}

/// Live-activity launch carries `teakSystemActivityId` but no URL/attribution.
/// The other ten keys must still be NSNull in to_h. Matches the canonical
/// `live_activity.json` fixture: an LA tap has no notification or attributed-
/// URL source, so every attributed slot stays null on the wire.
- (void)testLiveActivityLaunchDataEmitsAllElevenKeysWithOnlySystemActivityIdPopulated {
  NSString* systemActivityId = @"D3CBB9AF-7292-4FD9-B22D-DEAC3D033BD2";
  TeakLiveActivityLaunchData* data = [[TeakLiveActivityLaunchData alloc] initWithSystemActivityId:systemActivityId];
  NSDictionary* dict = [data to_h];

  [self assertCanonicalKeysAlwaysPresent:dict label:@"live_activity"];

  XCTAssertEqualObjects(dict[@"teakSystemActivityId"], systemActivityId);
  for (NSString* key in TeakCanonicalWireKeys()) {
    if ([key isEqualToString:@"teakSystemActivityId"]) continue;
    XCTAssertEqualObjects(dict[key], [NSNull null],
                          @"live_activity: %@ should be NSNull, got %@", key, dict[key]);
  }
}

#pragma mark - teakDeepLink publishes the resolved deep link

/// On the rewardlink path, the outer (short) launch URL carries a
/// `teak_deep_link` query param that points to the inner deep link the host
/// game routes on. The constructor uses the short link's query for the
/// teak_deep_link lookup; teakDeepLink must surface the inner link, not the
/// outer short link.
- (void)testTeakDeepLinkPublishesInnerDeepLinkForRewardlinkLaunch {
  NSURL* shortLink = [NSURL URLWithString:@"teaktest-app://r/abc?teak_rewardlink_id=42&teak_deep_link=teaktest-app%3A%2F%2Fpromo%2Fsummer"];
  NSURL* resolvedUrl = [NSURL URLWithString:@"teaktest-app://r/abc?teak_rewardlink_id=42"];
  TeakRewardlinkLaunchData* data = [[TeakRewardlinkLaunchData alloc] initWithUrl:resolvedUrl andShortLink:shortLink];

  NSDictionary* dict = [data to_h];

  XCTAssertEqualObjects(dict[@"teakDeepLink"], @"teaktest-app://promo/summer",
                        @"teakDeepLink must be the inner deepLink (teak_deep_link query value on the short link), not the outer rewardlink URL");
}

/// When the source URL carries no `teak_deep_link` query param, teakDeepLink
/// surfaces the resolved deep link directly (no inner-vs-outer distinction).
- (void)testTeakDeepLinkPublishesResolvedDeepLinkOnNotificationLaunch {
  NSURL* url = [NSURL URLWithString:@"teaktest-app://chest?teak_notif_id=12345&teak_creative_id=42"];
  TeakNotificationLaunchData* data = [[TeakNotificationLaunchData alloc] initWithUrl:url];

  NSDictionary* dict = [data to_h];

  XCTAssertEqualObjects(dict[@"teakDeepLink"], @"teaktest-app://chest?teak_notif_id=12345&teak_creative_id=42",
                        @"teakDeepLink must publish self.deepLink (the resolved deep link), gated by TeakLink_WillHandleDeepLink");
}

#pragma mark - teakOptOutCategory defaults to "teak" on attributed launches

/// On a notification launch where the source omitted `teak_opt_out_category`,
/// teakOptOutCategory must default to the literal string "teak". Cross-SDK
/// contract — Android publishes the same default, host games rely on a
/// non-null category bucket on every attributed launch.
- (void)testTeakOptOutCategoryDefaultsToTeakLiteralWhenAbsentOnNotification {
  NSURL* url = [NSURL URLWithString:@"teaktest-app://chest?teak_notif_id=12345&teak_creative_id=42&teak_reward_id=99"];
  TeakNotificationLaunchData* data = [[TeakNotificationLaunchData alloc] initWithUrl:url];

  NSDictionary* dict = [data to_h];

  XCTAssertEqualObjects(dict[@"teakOptOutCategory"], @"teak",
                        @"teakOptOutCategory must default to 'teak' when source omitted teak_opt_out_category");
}

/// When the source explicitly sets a category, that value rides on the wire
/// (no override).
- (void)testTeakOptOutCategoryRidesExplicitValueWhenPresent {
  NSURL* url = [NSURL URLWithString:@"teaktest-app://chest?teak_notif_id=12345&teak_opt_out_category=promos"];
  TeakNotificationLaunchData* data = [[TeakNotificationLaunchData alloc] initWithUrl:url];

  NSDictionary* dict = [data to_h];

  XCTAssertEqualObjects(dict[@"teakOptOutCategory"], @"promos");
}

#pragma mark - JSON serializability

/// The wire format requires JSON-encodable values: strings or null, no nested
/// types. NSDictionary with NSNull values must round-trip cleanly through
/// NSJSONSerialization. This guards the click-request session_attribution mint
/// path that JSON-encodes to_h before sending.
- (void)testToHIsJsonSerializableForEveryClass {
  NSArray* cases = @[
    [[TeakLaunchData alloc] init],
    [[TeakRewardlinkLaunchData alloc] initWithUrl:[NSURL URLWithString:@"teaktest-app://r/abc?teak_rewardlink_id=42"] andShortLink:nil],
    [[TeakNotificationLaunchData alloc] initWithUrl:[NSURL URLWithString:@"teaktest-app://chest?teak_notif_id=12345"]],
    [[TeakLiveActivityLaunchData alloc] initWithSystemActivityId:@"D3CBB9AF-7292-4FD9-B22D-DEAC3D033BD2"],
  ];

  for (TeakLaunchData* data in cases) {
    NSDictionary* dict = [data to_h];
    XCTAssertTrue([NSJSONSerialization isValidJSONObject:dict],
                  @"%@.to_h must be JSON-encodable", NSStringFromClass(data.class));
    NSError* err = nil;
    NSData* encoded = [NSJSONSerialization dataWithJSONObject:dict options:0 error:&err];
    XCTAssertNotNil(encoded, @"%@: JSON encode failed: %@", NSStringFromClass(data.class), err);
  }
}

@end
