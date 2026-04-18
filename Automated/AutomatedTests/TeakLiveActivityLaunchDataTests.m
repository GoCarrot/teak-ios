#import <XCTest/XCTest.h>

#import <Teak/Teak.h>

#import "TeakLaunchData.h"

@import OCHamcrest;
@import OCMockito;

// Re-expose internal initializer for testing.
@interface TeakLiveActivityLaunchData (Testing)
- (id)initWithSystemActivityId:(NSString*)systemActivityId;
@end

@interface TeakLiveActivityLaunchDataTests : XCTestCase
@end

@implementation TeakLiveActivityLaunchDataTests

static NSString* const kSystemActivityId = @"D3CBB9AF-7292-4FD9-B22D-DEAC3D033BD2";

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

- (void)testFromUserActivityHandlesBrowsingWeb {
  NSUserActivity* activity = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
  activity.webpageURL = [NSURL URLWithString:@"https://example.com/foo"];
  TeakLaunchDataOperation* op = [TeakLaunchDataOperation fromUserActivity:activity];
  XCTAssertNotNil(op, @"Browsing-web activities should still produce a launch data operation");
}

@end
