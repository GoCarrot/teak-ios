#import <Foundation/Foundation.h>

typedef enum : int {
  kTeakRewardStatusUnknown = -1,              ///< An unknown error occured while processing the reward.
  kTeakRewardStatusGrantReward = 0,           ///< Valid reward claim, grant the user the reward.
  kTeakRewardStatusSelfClick = 1,             ///< The user has attempted to claim a reward from their own social post.
  kTeakRewardStatusAlreadyClicked = 2,        ///< The user has already been issued this reward.
  kTeakRewardStatusTooManyClicks = 3,         ///< The reward has already been claimed its maximum number of times globally.
  kTeakRewardStatusExceedMaxClicksForDay = 4, ///< The user has already claimed their maximum number of rewards of this type for the day.
  kTeakRewardStatusExpired = 5,               ///< This reward has expired and is no longer valid.
  kTeakRewardStatusInvalidPost = 6,           ///< Teak does not recognize this reward id.
} TeakRewardStatus;

typedef void (^RewardCompleted)(void);

@interface TeakReward : NSObject
@property (atomic, readonly) BOOL completed;
@property (nonatomic, readonly) int rewardStatus;
@property (strong, nonatomic, readonly) NSDictionary* _Nonnull json;
@property (nonatomic, copy) RewardCompleted _Nullable onComplete;

+ (nullable TeakReward*)rewardForRewardId:(nonnull NSString*)teakRewardId;
+ (void)checkAttributionForRewardAndDispatchEvents:(nonnull NSDictionary*)attribution;
@end
