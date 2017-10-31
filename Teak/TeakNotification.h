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
@property (strong, nonatomic, readonly) NSString* _Nullable teakNotifId;
@property (strong, nonatomic, readonly) NSString* _Nullable status;
@property (strong, nonatomic, readonly) NSString* _Nullable teakRewardId;
@property (strong, nonatomic, readonly) NSDictionary* _Nullable originalJson;
@property (strong, nonatomic, readonly) NSURL* _Nullable teakDeepLink;
@property (atomic, readonly) BOOL completed;

- (nullable TeakNotification*)initWithDictionary:(nonnull NSDictionary*)dictionary;

+ (nullable TeakNotification*)scheduleNotificationForCreative:(nonnull NSString*)creativeId withMessage:(nonnull NSString*)message secondsFromNow:(int64_t)delay;
+ (nullable TeakNotification*)cancelScheduledNotification:(nonnull NSString*)scheduleId;
+ (nullable TeakNotification*)cancelAll;
@end
