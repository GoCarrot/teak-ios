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
#import <Teak/TeakReward.h>

void TeakSetDebugOutputEnabled(int enabled) {
  [Teak sharedInstance].enableDebugOutput = (enabled > 0);
}

void TeakIdentifyUser(const char* userId) {
  [[Teak sharedInstance] identifyUser:[NSString stringWithUTF8String:userId]];
}

void TeakTrackEvent(const char* actionId, const char* objectTypeId, const char* objectInstanceId) {
  [[Teak sharedInstance] trackEventWithActionId:actionId == NULL ? nil : [NSString stringWithUTF8String:actionId]
                                forObjectTypeId:objectTypeId == NULL ? nil : [NSString stringWithUTF8String:objectTypeId]
                            andObjectInstanceId:objectInstanceId == NULL ? nil : [NSString stringWithUTF8String:objectInstanceId]];
}

void TeakAssignWaitForDeepLinkOperation(NSOperation* waitForDeepLinkOp) {
  [Teak sharedInstance].waitForDeepLinkOperation = waitForDeepLinkOp;
}

void TeakRunNSOperation(NSOperation* op) {
  [[Teak sharedInstance].operationQueue addOperation:op];
}

TeakNotification* TeakNotificationSchedule(const char* creativeId, const char* message, int64_t delay) {
  return [TeakNotification scheduleNotificationForCreative:[NSString stringWithUTF8String:creativeId]
                                               withMessage:[NSString stringWithUTF8String:message]
                                            secondsFromNow:delay];
}

TeakNotification* TeakNotificationCancel(const char* scheduleId) {
  return [TeakNotification cancelScheduledNotification:[NSString stringWithUTF8String:scheduleId]];
}

TeakNotification* TeakNotificationCancelAll() {
  return [TeakNotification cancelAll];
}

BOOL TeakNotificationHasReward(TeakNotification* notif) {
  return ([notif.originalJson objectForKey:@"teakRewardId"] != nil);
}

BOOL TeakNotificationIsCompleted(TeakNotification* notif) {
  return notif.completed;
}

const char* TeakNotificationGetTeakNotifId(TeakNotification* notif) {
  return [notif.teakNotifId UTF8String];
}

const char* TeakNotificationGetStatus(TeakNotification* notif) {
  return [notif.status UTF8String];
}

TeakReward* TeakRewardRewardForId(NSString* teakRewardId) {
  return [TeakReward rewardForRewardId:teakRewardId];
}

BOOL TeakRewardIsCompleted(TeakReward* reward) {
  return reward.completed;
}

const char* TeakRewardGetJson(TeakReward* reward) {
  if (reward == nil || reward.json == nil) {
    return "";
  }

  NSError* error = nil;
  NSData* jsonData = [NSJSONSerialization dataWithJSONObject:reward.json
                                                     options:0
                                                       error:&error];

  if (error != nil) {
    TeakLog_e(@"reward.error.json", @{@"error" : [error localizedDescription]});
  } else {
    NSString* jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    return [jsonString UTF8String];
  }
  return "";
}

void TeakRegisterRoute(const char* route, const char* name, const char* description, TeakLinkBlock block) {
  [TeakLink registerRoute:[NSString stringWithUTF8String:route] name:[NSString stringWithUTF8String:name] description:[NSString stringWithUTF8String:description] block:block];
}

BOOL TeakOpenSettingsAppToThisAppsSettings() {
  return [[Teak sharedInstance] openSettingsAppToThisAppsSettings];
}

BOOL TeakHasUserDisabledPushNotifications() {
  return [[Teak sharedInstance] hasUserDisabledPushNotifications];
}

void TeakSetBadgeCount(int count) {
  [[Teak sharedInstance] setApplicationBadgeNumber:count];
}

void TeakSetNumericAttribute(const char* cstr_key, double value) {
  NSString* key = [NSString stringWithUTF8String:cstr_key];
  if (key != nil) {
    [[Teak sharedInstance] setNumericAttribute:value forKey:key];
  }
}

void TeakSetStringAttribute(const char* cstr_key, const char* cstr_value) {
  NSString* key = [NSString stringWithUTF8String:cstr_key];
  NSString* value = [NSString stringWithUTF8String:cstr_value];
  if (key != nil) {
    [[Teak sharedInstance] setStringAttribute:value forKey:key];
  }
}

const char* TeakGetAppConfiguration() {
  return [[[Teak sharedInstance] getAppConfiguration] UTF8String];
}

const char* TeakGetDeviceConfiguration() {
  return [[[Teak sharedInstance] getDeviceConfiguration] UTF8String];
}
