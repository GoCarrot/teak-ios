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

#import "Teak+Internal.h"
#import <Teak/TeakNotification.h>

void TeakSetDebugOutputEnabled(int enabled)
{
   [Teak sharedInstance].enableDebugOutput = (enabled > 0);
}

void TeakIdentifyUser(const char* userId)
{
   [[Teak sharedInstance] identifyUser:[NSString stringWithUTF8String:userId]];
}

void TeakTrackEvent(const char* actionId, const char* objectTypeId, const char* objectInstanceId)
{
   [[Teak sharedInstance] trackEventWithActionId:[NSString stringWithUTF8String:actionId]
                                 forObjectTypeId:[NSString stringWithUTF8String:objectTypeId]
                             andObjectInstanceId:[NSString stringWithUTF8String:objectInstanceId]];
}

TeakNotification* TeakNotificationFromTeakNotifId(const char* teakNotifId)
{
   return [TeakNotification notificationFromTeakNotifId:[NSString stringWithUTF8String:teakNotifId]];
}

TeakNotification* TeakNotificationSchedule(const char* creativeId, const char* message, uint64_t delay)
{
   return [TeakNotification scheduleNotificationForCreative:[NSString stringWithUTF8String:creativeId]
                                                withMessage:[NSString stringWithUTF8String:message]
                                             secondsFromNow:delay];
}

TeakNotification* TeakNotificationCancel(const char* scheduleId)
{
   return [TeakNotification cancelScheduledNotification:[NSString stringWithUTF8String:scheduleId]];
}

TeakReward* TeakNotificationConsume(TeakNotification* notif)
{
   return [notif consume];
}

BOOL TeakNotificationHasReward(TeakNotification* notif)
{
   return ([notif.originalJson objectForKey:@"teakRewardId"] != nil);
}

BOOL TeakNotificationIsCompleted(TeakNotification* notif)
{
   return notif.completed;
}

const char* TeakNotificationGetTeakNotifId(TeakNotification* notif)
{
   return [notif.teakNotifId UTF8String];
}

BOOL TeakRewardIsCompleted(TeakReward* reward)
{
   return reward.completed;
}

int TeakRewardGetStatus(TeakReward* reward)
{
   return reward.rewardStatus;
}

const char* TeakRewardGetJson(TeakReward* reward)
{
   return [reward.json UTF8String];
}
