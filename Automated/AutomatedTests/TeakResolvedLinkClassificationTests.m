#import <XCTest/XCTest.h>

#import <Teak/Teak.h>

#import "TeakLaunchData.h"

@import OCHamcrest;
@import OCMockito;

// Re-expose the pure classifier so tests can exercise it without the network
// round-trip in resolveUniversalLink:. resolvedUrl is what the server returned as
// iOSPath (nil when omitted); shortLink is the original universal/launch link.
@interface TeakLaunchDataOperation (Testing)
+ (TeakLaunchData*)launchDataFromResolvedUrl:(NSURL*)resolvedUrl shortLink:(NSURL*)shortLink;
@end

@interface TeakResolvedLinkClassificationTests : XCTestCase
@end

@implementation TeakResolvedLinkClassificationTests

#pragma mark - iOSPath present (happy path — behavior must be unchanged)

/// Server returned an iOSPath carrying reward params: classify from the resolved
/// deep link, keep the short link as launchUrl.
- (void)testResolvedRewardLinkClassifiesFromResolvedUrl {
  NSURL* resolvedUrl = [NSURL URLWithString:@"teaktest-app://reward?teak_rewardlink_id=abc&teak_reward_id=99"];
  NSURL* shortLink = [NSURL URLWithString:@"https://test.jckpt.com/x"];

  TeakLaunchData* data = [TeakLaunchDataOperation launchDataFromResolvedUrl:resolvedUrl shortLink:shortLink];

  XCTAssertTrue([data isKindOfClass:[TeakRewardlinkLaunchData class]]);
  TeakAttributedLaunchData* attributed = (TeakAttributedLaunchData*)data;
  XCTAssertEqualObjects(attributed.launchUrl.absoluteString, shortLink.absoluteString);
  XCTAssertEqualObjects(attributed.deepLink.absoluteString, resolvedUrl.absoluteString);
  XCTAssertEqualObjects(attributed.rewardId, @"99");
  XCTAssertEqualObjects(attributed.creativeId, @"abc");
}

/// Server returned an iOSPath carrying a notif id: classify as a notification launch.
- (void)testResolvedNotifLinkClassifiesFromResolvedUrl {
  NSURL* resolvedUrl = [NSURL URLWithString:@"teaktest-app://open?teak_notif_id=555"];
  NSURL* shortLink = [NSURL URLWithString:@"https://test.jckpt.com/x"];

  TeakLaunchData* data = [TeakLaunchDataOperation launchDataFromResolvedUrl:resolvedUrl shortLink:shortLink];

  XCTAssertTrue([data isKindOfClass:[TeakNotificationLaunchData class]]);
  XCTAssertEqualObjects(((TeakNotificationLaunchData*)data).sourceSendId, @"555");
}

/// Server resolved to a plain deep link with no teak_* params: unattributed launch,
/// short link retained as launchUrl.
- (void)testResolvedPlainLinkIsUnattributed {
  NSURL* resolvedUrl = [NSURL URLWithString:@"teaktest-app://home"];
  NSURL* shortLink = [NSURL URLWithString:@"https://test.jckpt.com/x"];

  TeakLaunchData* data = [TeakLaunchDataOperation launchDataFromResolvedUrl:resolvedUrl shortLink:shortLink];

  XCTAssertFalse([data isKindOfClass:[TeakAttributedLaunchData class]]);
  XCTAssertEqualObjects(data.launchUrl.absoluteString, shortLink.absoluteString);
}

#pragma mark - iOSPath absent (the fix — classify from the original launch link)

/// THE regression guard. When the server omits iOSPath, resolvedUrl is nil and the
/// reward params live on the original launch link. Before the `?: shortLink` fallback
/// this dropped to a plain TeakLaunchData and lost reward attribution; reverting the
/// fix makes this assertion fail.
- (void)testAbsentIOSPathRewardClassifiesFromShortLink {
  NSURL* shortLink = [NSURL URLWithString:@"https://test.jckpt.com/x?teak_rewardlink_id=abc&teak_reward_id=99"];

  TeakLaunchData* data = [TeakLaunchDataOperation launchDataFromResolvedUrl:nil shortLink:shortLink];

  XCTAssertTrue([data isKindOfClass:[TeakRewardlinkLaunchData class]],
                @"reward attribution on the launch link must survive an absent iOSPath");
  TeakAttributedLaunchData* attributed = (TeakAttributedLaunchData*)data;
  XCTAssertEqualObjects(attributed.launchUrl.absoluteString, shortLink.absoluteString);
  XCTAssertEqualObjects(attributed.deepLink.absoluteString, shortLink.absoluteString);
  XCTAssertEqualObjects(attributed.rewardId, @"99");
  XCTAssertEqualObjects(attributed.creativeId, @"abc");
}

/// Same fallback for notification links carried on the launch link itself.
- (void)testAbsentIOSPathNotifClassifiesFromShortLink {
  NSURL* shortLink = [NSURL URLWithString:@"https://test.jckpt.com/x?teak_notif_id=555"];

  TeakLaunchData* data = [TeakLaunchDataOperation launchDataFromResolvedUrl:nil shortLink:shortLink];

  XCTAssertTrue([data isKindOfClass:[TeakNotificationLaunchData class]]);
  XCTAssertEqualObjects(((TeakNotificationLaunchData*)data).sourceSendId, @"555");
}

/// Absent iOSPath with no teak_* params on the launch link is still unattributed —
/// the fallback must not manufacture attribution out of a plain link.
- (void)testAbsentIOSPathNoTeakParamsIsUnattributed {
  NSURL* shortLink = [NSURL URLWithString:@"https://test.jckpt.com/x"];

  TeakLaunchData* data = [TeakLaunchDataOperation launchDataFromResolvedUrl:nil shortLink:shortLink];

  XCTAssertFalse([data isKindOfClass:[TeakAttributedLaunchData class]]);
  XCTAssertEqualObjects(data.launchUrl.absoluteString, shortLink.absoluteString);
}

@end
