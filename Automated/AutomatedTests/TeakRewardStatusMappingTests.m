#import <XCTest/XCTest.h>

#import "TeakReward.h"

@interface TeakReward (TestAccess)
+ (TeakRewardStatus)rewardStatusForString:(NSString*)status;
@end

@interface TeakRewardStatusMappingTests : XCTestCase
@end

@implementation TeakRewardStatusMappingTests

- (void)testMapsExistingStatusStrings {
  XCTAssertEqual([TeakReward rewardStatusForString:@"grant_reward"], kTeakRewardStatusGrantReward);
  XCTAssertEqual([TeakReward rewardStatusForString:@"self_click"], kTeakRewardStatusSelfClick);
  XCTAssertEqual([TeakReward rewardStatusForString:@"already_clicked"], kTeakRewardStatusAlreadyClicked);
  XCTAssertEqual([TeakReward rewardStatusForString:@"too_many_clicks"], kTeakRewardStatusTooManyClicks);
  XCTAssertEqual([TeakReward rewardStatusForString:@"exceed_max_clicks_for_day"], kTeakRewardStatusExceedMaxClicksForDay);
  XCTAssertEqual([TeakReward rewardStatusForString:@"expired"], kTeakRewardStatusExpired);
  XCTAssertEqual([TeakReward rewardStatusForString:@"invalid_post"], kTeakRewardStatusInvalidPost);
}

- (void)testMapsPlayerIneligible {
  XCTAssertEqual([TeakReward rewardStatusForString:@"player_ineligible"], kTeakRewardStatusPlayerIneligible);
  XCTAssertEqual((int)kTeakRewardStatusPlayerIneligible, 7);
}

- (void)testMapsNoRewardAvailable {
  XCTAssertEqual([TeakReward rewardStatusForString:@"no_reward_available"], kTeakRewardStatusNoRewardAvailable);
  XCTAssertEqual((int)kTeakRewardStatusNoRewardAvailable, 8);
}

- (void)testMapsClaimModeUnsupported {
  XCTAssertEqual([TeakReward rewardStatusForString:@"claim_mode_unsupported"], kTeakRewardStatusClaimModeUnsupported);
  XCTAssertEqual((int)kTeakRewardStatusClaimModeUnsupported, 9);
}

- (void)testUnknownStringMapsToUnknown {
  XCTAssertEqual([TeakReward rewardStatusForString:@"some_future_status"], kTeakRewardStatusUnknown);
  XCTAssertEqual([TeakReward rewardStatusForString:@""], kTeakRewardStatusUnknown);
}

@end
