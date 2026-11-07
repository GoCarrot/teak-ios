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
+ (NSDictionary*)noIosPathLogDataForUrl:(NSURL*)url responseData:(NSData*)data;
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

#pragma mark - updateDeepLink:withLaunchLink: (server-enriched deep link on an unattributed launch)

/// An unattributed launch whose users.json reply carries a reward deep link is
/// re-classified from that link; the launch link sent in the request must survive as
/// launchUrl. Reverting the reward branch to a nil short link makes this fail.
- (void)testUpdateDeepLinkRewardKeepsLaunchLink {
  TeakLaunchDataOperation* op = [self finishedUnattributedOperation];
  NSURL* launchLink = [NSURL URLWithString:@"https://test.jckpt.com/x"];
  NSURL* enriched = [NSURL URLWithString:@"teaktest-app://chest?teak_rewardlink_id=abc&teak_reward_id=99"];

  TeakLaunchData* data = [op updateDeepLink:enriched withLaunchLink:launchLink].result;

  XCTAssertTrue([data isKindOfClass:[TeakRewardlinkLaunchData class]]);
  TeakAttributedLaunchData* attributed = (TeakAttributedLaunchData*)data;
  XCTAssertEqualObjects(attributed.launchUrl.absoluteString, launchLink.absoluteString);
  XCTAssertEqualObjects(attributed.deepLink.absoluteString, enriched.absoluteString);
  XCTAssertEqualObjects(attributed.rewardId, @"99");
  XCTAssertEqualObjects(attributed.creativeId, @"abc");
  XCTAssertEqualObjects(data.sessionAttribution[@"launch_link"], launchLink.absoluteString);
}

/// No launch link in the request means none is invented.
- (void)testUpdateDeepLinkRewardWithoutLaunchLinkHasNoLaunchUrl {
  TeakLaunchDataOperation* op = [self finishedUnattributedOperation];
  NSURL* enriched = [NSURL URLWithString:@"teaktest-app://chest?teak_rewardlink_id=abc"];

  TeakLaunchData* data = [op updateDeepLink:enriched withLaunchLink:nil].result;

  XCTAssertTrue([data isKindOfClass:[TeakRewardlinkLaunchData class]]);
  XCTAssertNil(data.launchUrl);
  XCTAssertNil(data.sessionAttribution[@"launch_link"]);
}

/// Notification links don't carry a launch link through re-classification, matching
/// teak-android.
- (void)testUpdateDeepLinkNotifDoesNotKeepLaunchLink {
  TeakLaunchDataOperation* op = [self finishedUnattributedOperation];
  NSURL* launchLink = [NSURL URLWithString:@"https://test.jckpt.com/x"];
  NSURL* enriched = [NSURL URLWithString:@"teaktest-app://open?teak_notif_id=555"];

  TeakLaunchData* data = [op updateDeepLink:enriched withLaunchLink:launchLink].result;

  XCTAssertTrue([data isKindOfClass:[TeakNotificationLaunchData class]]);
  XCTAssertNil(data.launchUrl);
}

- (TeakLaunchDataOperation*)finishedUnattributedOperation {
  TeakLaunchDataOperation* op = [TeakLaunchDataOperation unattributed];
  NSOperationQueue* queue = [[NSOperationQueue alloc] init];
  [queue addOperation:op];
  [queue waitUntilAllOperationsAreFinished];
  return op;
}

#pragma mark - no_ios_path log payload

/// UTF-16 JSON is valid JSON but not valid UTF-8, so the body can't be decoded as a
/// string. The payload must still build (no nil in the dictionary) and log as NSNull.
- (void)testNoIosPathLogPayloadSurvivesNonUtf8Body {
  NSURL* url = [NSURL URLWithString:@"https://test.jckpt.com/x"];
  NSData* body = [@"{\"foo\":\"bar\"}" dataUsingEncoding:NSUTF16StringEncoding];

  NSDictionary* payload = nil;
  XCTAssertNoThrow(payload = [TeakLaunchDataOperation noIosPathLogDataForUrl:url responseData:body]);

  XCTAssertEqualObjects(payload[@"url"], url.absoluteString);
  XCTAssertEqualObjects(payload[@"response"], [NSNull null]);
}

/// A UTF-8 body is logged verbatim.
- (void)testNoIosPathLogPayloadKeepsUtf8Body {
  NSURL* url = [NSURL URLWithString:@"https://test.jckpt.com/x"];
  NSString* json = @"{\"foo\":\"bar\"}";
  NSData* body = [json dataUsingEncoding:NSUTF8StringEncoding];

  NSDictionary* payload = [TeakLaunchDataOperation noIosPathLogDataForUrl:url responseData:body];

  XCTAssertEqualObjects(payload[@"url"], url.absoluteString);
  XCTAssertEqualObjects(payload[@"response"], json);
}

@end
