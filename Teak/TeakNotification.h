/* Teak -- Copyright (C) 2016 GoCarrot Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#import <Foundation/Foundation.h>

@class TeakReward;

@interface TeakNotification : NSObject
@property (strong, nonatomic, readonly) NSString* _Nullable     teakNotifId;
@property (strong, nonatomic, readonly) NSDictionary* _Nullable originalJson;
@property (strong, nonatomic, readonly) NSURL* _Nullable        deepLink;
@property (atomic, readonly)            BOOL                    completed;

- (nullable TeakReward*)consume;
- (nullable TeakNotification*)initWithDictionary:(nonnull NSDictionary*)dictionary;

+ (nullable TeakNotification*)scheduleNotificationForCreative:(nonnull NSString*)creativeId withMessage:(nonnull NSString*)message secondsFromNow:(uint64_t)delay;
+ (nullable TeakNotification*)cancelScheduledNotification:(nonnull NSString*)scheduleId;
@end

typedef enum : int
{
   kTeakRewardStatusUnknown = -1,       ///< An unknown error occured while processing the reward.
   kTeakRewardStatusGrantReward = 0,    ///< Valid reward claim, grant the user the reward.
   kTeakRewardStatusSelfClick = 1,      ///< The user has attempted to claim a reward from their own social post.
   kTeakRewardStatusAlreadyClicked = 2, ///< The user has already been issued this reward.
   kTeakRewardStatusTooManyClicks = 3,  ///< The reward has already been claimed its maximum number of times globally.
   kTeakRewardStatusExceedMaxClicksForDay = 4, ///< The user has already claimed their maximum number of rewards of this type for the day.
   kTeakRewardStatusExpired = 5,        ///< This reward has expired and is no longer valid.
   kTeakRewardStatusInvalidPost = 6,    ///< Teak does not recognize this reward id.
} TeakRewardStatus;

@interface TeakReward : NSObject
@property (atomic, readonly)            BOOL               completed;
@property (nonatomic, readonly)         int                rewardStatus;
@property (strong, nonatomic, readonly) NSString* _Nonnull json;
@end
