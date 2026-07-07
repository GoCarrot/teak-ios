#import <XCTest/XCTest.h>

#import "TeakReward.h"
#import "TeakSession.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// The session pointer that whenUserIdIsReadyRun: reads. Kept nil here so
// rewardForRewardId:onComplete:'s internal whenUserIdIsReadyRun: call only
// enqueues its block instead of dispatching a real network request.
extern TeakSession* currentSession;

// onCompleteWithReward is private (declared only in TeakReward.m's class extension);
// re-exposed here per the project convention of redeclaring internal properties in
// the test file rather than importing Teak+Internal.h.
@interface TeakReward (RewardTests)
@property (nonatomic, copy, readonly) RewardCompletedWithReward onCompleteWithReward;
@end

@interface TeakRewardTests : XCTestCase
@end

@implementation TeakRewardTests

- (void)setUp {
  currentSession = nil;
}

- (void)tearDown {
  currentSession = nil;
  [super tearDown];
}

// onCompleteWithReward must already be set by the time rewardForRewardId:onComplete:
// returns — assigned before whenUserIdIsReadyRun: is even called, so there is no
// window for a fast network reply to beat the assignment (the old +rewardForRewardId:
// + post-hoc `.onComplete =` pattern had exactly that window).
- (void)testOnCompleteWithRewardIsAssignedBeforeAnyDispatch {
  __block BOOL fired = NO;
  TeakReward* reward = [TeakReward rewardForRewardId:@"reward-1"
                                           onComplete:^(TeakReward* r) {
                                             fired = YES;
                                           }];

  XCTAssertNotNil(reward);
  XCTAssertNotNil(reward.onCompleteWithReward,
                  @"onCompleteWithReward must be assigned synchronously inside the factory");

  reward.onCompleteWithReward(reward);
  XCTAssertTrue(fired, @"the assigned callback must be the one passed in");
}

- (void)testRewardForRewardIdOnCompleteReturnsNilForNilRewardId {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
  XCTAssertNil([TeakReward rewardForRewardId:nil onComplete:nil]);
#pragma clang diagnostic pop
}

- (void)testRewardForRewardIdOnCompleteReturnsNilForEmptyRewardId {
  XCTAssertNil([TeakReward rewardForRewardId:@"" onComplete:nil]);
}

- (void)testRewardForRewardIdOnCompleteInitializesUnclaimedState {
  TeakReward* reward = [TeakReward rewardForRewardId:@"reward-1" onComplete:nil];
  XCTAssertFalse(reward.completed);
  XCTAssertEqual(reward.rewardStatus, kTeakRewardStatusUnknown);
}

// The single-arg factory is kept for source/binary compatibility (TeakReward.h
// is a shipped public header) and must keep working exactly as before.
- (void)testLegacyRewardForRewardIdStillConstructsAReward {
  TeakReward* reward = [TeakReward rewardForRewardId:@"reward-1"];

  XCTAssertNotNil(reward);
  XCTAssertFalse(reward.completed);
  XCTAssertEqual(reward.rewardStatus, kTeakRewardStatusUnknown);
}

@end
