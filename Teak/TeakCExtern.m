#import "Teak+Internal.h"
#import <Teak/TeakNotification.h>
#import <Teak/TeakReward.h>

void TeakSetDebugOutputEnabled(int enabled) {
  [Teak sharedInstance].enableDebugOutput = (enabled > 0);
}

void TeakIdentifyUser(const char* userId, const char* optOutJsonArray) {
  NSArray* optOutList = @[];
  if (optOutJsonArray != NULL) {
    @try {
      NSError* error = nil;
      NSData* jsonData = [[NSString stringWithUTF8String:optOutJsonArray] dataUsingEncoding:NSUTF8StringEncoding];
      optOutList = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:&error];
      if (error != nil || ![optOutList isKindOfClass:NSArray.class]) optOutList = @[];
    } @catch (NSException* ignored) {
    }
  }

  [[Teak sharedInstance] identifyUser:[NSString stringWithUTF8String:userId] withOptOutList:optOutList];
}

void TeakTrackEvent(const char* actionId, const char* objectTypeId, const char* objectInstanceId) {
  [[Teak sharedInstance] trackEventWithActionId:actionId == NULL ? nil : [NSString stringWithUTF8String:actionId]
                                forObjectTypeId:objectTypeId == NULL ? nil : [NSString stringWithUTF8String:objectTypeId]
                            andObjectInstanceId:objectInstanceId == NULL ? nil : [NSString stringWithUTF8String:objectInstanceId]];
}

void TeakIncrementEvent(const char* actionId, const char* objectTypeId, const char* objectInstanceId, uint32_t count) {
  [[Teak sharedInstance] incrementEventWithActionId:actionId == NULL ? nil : [NSString stringWithUTF8String:actionId]
                                    forObjectTypeId:objectTypeId == NULL ? nil : [NSString stringWithUTF8String:objectTypeId]
                                andObjectInstanceId:objectInstanceId == NULL ? nil : [NSString stringWithUTF8String:objectInstanceId]
                                              count:count];
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

TeakNotification* TeakNotificationScheduleLongDistanceWithNSArray(const char* creativeId, int64_t delay, NSArray* userIds) {
  return [TeakNotification scheduleNotificationForCreative:[NSString stringWithUTF8String:creativeId]
                                            secondsFromNow:delay
                                                forUserIds:userIds];
}

TeakNotification* TeakNotificationScheduleLongDistance(const char* creativeId, int64_t delay, const char* inUserIds[], int inUserIdCount) {
  NSMutableArray* userIds = [[NSMutableArray alloc] init];
  for (int i = 0; i < inUserIdCount; i++) {
    [userIds addObject:[NSString stringWithUTF8String:inUserIds[i]]];
  }
  return TeakNotificationScheduleLongDistanceWithNSArray(creativeId, delay, userIds);
}

TeakNotification* TeakNotificationCancel(const char* scheduleId) {
  return [TeakNotification cancelScheduledNotification:[NSString stringWithUTF8String:scheduleId]];
}

TeakNotification* TeakNotificationCancelAll() {
  return [TeakNotification cancelAll];
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

BOOL TeakRewardIsCompleted(TeakReward* reward) {
  return reward.completed;
}

void TeakRegisterRoute(const char* route, const char* name, const char* description, TeakLinkBlock block) {
  [TeakLink registerRoute:[NSString stringWithUTF8String:route] name:[NSString stringWithUTF8String:name] description:[NSString stringWithUTF8String:description] block:block];
}

BOOL TeakOpenSettingsAppToThisAppsSettings() {
  return [[Teak sharedInstance] openSettingsAppToThisAppsSettings];
}

int TeakGetNotificationState() {
  return [[Teak sharedInstance] notificationState];
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

void TeakReportTestException() {
  [[Teak sharedInstance] reportTestException];
}

BOOL TeakRequestProvisionalPushAuthorization() {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
  if (iOS12OrGreater() && NSClassFromString(@"UNUserNotificationCenter") != nil) {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    UNAuthorizationOptions authOptions = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge | TeakUNAuthorizationOptionProvisional;
    [center requestAuthorizationWithOptions:authOptions
                          completionHandler:^(BOOL granted, NSError* _Nullable error) {
                            if (granted) {
                              dispatch_async(dispatch_get_main_queue(), ^{
                                [[UIApplication sharedApplication] registerForRemoteNotifications];
                              });
                            }
                          }];
    return YES;
  }
#pragma clang diagnostic pop
  return NO;
}
