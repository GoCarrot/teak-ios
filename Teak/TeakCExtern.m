#import "Teak+Internal.h"
#import <Teak/TeakNotification.h>
#import <Teak/TeakReward.h>

void TeakSetDebugOutputEnabled(int enabled) {
  [Teak sharedInstance].enableDebugOutput = (enabled > 0);
}

void TeakIdentifyUser(const char* userId, const char* userConfigurationJson) {
  TeakUserConfiguration* userConfiguration = [[TeakUserConfiguration alloc] init];
  if (userConfigurationJson != NULL) {
    @try {
      NSError* error = nil;
      NSData* jsonData = [[NSString stringWithUTF8String:userConfigurationJson] dataUsingEncoding:NSUTF8StringEncoding];
      NSDictionary* configurationDict = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:&error];
      userConfiguration.email = configurationDict[@"email"];
      userConfiguration.facebookId = configurationDict[@"facebook_id"];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      userConfiguration.optOutFacebook = [configurationDict[@"opt_out_facebook"] boolValue];
#pragma clang diagnostic pop
      userConfiguration.optOutIdfa = [configurationDict[@"opt_out_idfa"] boolValue];
      userConfiguration.optOutPushKey = [configurationDict[@"opt_out_push_key"] boolValue];
    } @catch (NSException* ignored) {
    }
  }

  [[Teak sharedInstance] identifyUser:[NSString stringWithUTF8String:userId]
                    withConfiguration:userConfiguration];
}

void TeakLogout(void) {
  [[Teak sharedInstance] logout];
}

void TeakDeleteEmail(void) {
  [[Teak sharedInstance] deleteEmail];
}

void TeakRefreshPushTokenIfAuthorized(void) {
  [[Teak sharedInstance] refreshPushTokenIfAuthorized];
}

void TeakTrackEvent(const char* actionId, const char* objectTypeId, const char* objectInstanceId) {
  [[Teak sharedInstance] trackEventWithActionId:actionId == NULL ? nil : [NSString stringWithUTF8String:actionId]
                                forObjectTypeId:objectTypeId == NULL ? nil : [NSString stringWithUTF8String:objectTypeId]
                            andObjectInstanceId:objectInstanceId == NULL ? nil : [NSString stringWithUTF8String:objectInstanceId]];
}

void TeakIncrementEvent(const char* actionId, const char* objectTypeId, const char* objectInstanceId, int64_t count) {
  [[Teak sharedInstance] incrementEventWithActionId:actionId == NULL ? nil : [NSString stringWithUTF8String:actionId]
                                    forObjectTypeId:objectTypeId == NULL ? nil : [NSString stringWithUTF8String:objectTypeId]
                                andObjectInstanceId:objectInstanceId == NULL ? nil : [NSString stringWithUTF8String:objectInstanceId]
                                              count:count];
}

void TeakProcessDeepLinks(void) {
  [[Teak sharedInstance] processDeepLinks];
}

TeakOperation* TeakNotificationSchedulePersonalizationData(const char* creativeId, int64_t delay, const char* personalizationDataJson) {
  NSError* error = nil;
  NSDictionary* personalizationData = nil;
  if (personalizationDataJson != nil) {
    NSData* jsonData = [[NSString stringWithUTF8String:personalizationDataJson] dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary* personalizationData = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:&error];
  }

  return [TeakNotification scheduleNotificationForCreative:[NSString stringWithUTF8String:creativeId]
                                            secondsFromNow:delay
                                       personalizationData:personalizationData];
}

TeakNotification* TeakNotificationSchedule(const char* creativeId, const char* message, int64_t delay) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  return [TeakNotification scheduleNotificationForCreative:[NSString stringWithUTF8String:creativeId]
                                               withMessage:[NSString stringWithUTF8String:message]
                                            secondsFromNow:delay];
#pragma clang diagnostic pop
}

TeakNotification* TeakNotificationScheduleLongDistanceWithNSArray(const char* creativeId, int64_t delay, NSArray* userIds) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  return [TeakNotification scheduleNotificationForCreative:[NSString stringWithUTF8String:creativeId]
                                            secondsFromNow:delay
                                                forUserIds:userIds];
#pragma clang diagnostic pop
}

TeakNotification* TeakNotificationScheduleLongDistance(const char* creativeId, int64_t delay, const char* inUserIds[], int inUserIdCount) {
  NSMutableArray* userIds = [[NSMutableArray alloc] init];
  for (int i = 0; i < inUserIdCount; i++) {
    [userIds addObject:[NSString stringWithUTF8String:inUserIds[i]]];
  }
  return TeakNotificationScheduleLongDistanceWithNSArray(creativeId, delay, userIds);
}

TeakNotification* TeakNotificationCancel(const char* scheduleId) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  return [TeakNotification cancelScheduledNotification:[NSString stringWithUTF8String:scheduleId]];
#pragma clang diagnostic pop
}

TeakNotification* TeakNotificationCancelAll(void) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  return [TeakNotification cancelAll];
#pragma clang diagnostic pop
}

BOOL TeakNotificationIsCompleted(TeakNotification* notif) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  return notif.completed;
#pragma clang diagnostic pop
}

const char* TeakNotificationGetTeakNotifId(TeakNotification* notif) {
  return [notif.teakNotifId UTF8String];
}

const char* TeakNotificationGetStatus(TeakNotification* notif) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  return [notif.status UTF8String];
#pragma clang diagnostic pop
}

BOOL TeakRewardIsCompleted(TeakReward* reward) {
  return reward.completed;
}

void TeakRegisterRoute(const char* route, const char* name, const char* description, TeakLinkBlock block) {
  [TeakLink registerRoute:[NSString stringWithUTF8String:route] name:[NSString stringWithUTF8String:name] description:[NSString stringWithUTF8String:description] block:block];
}

BOOL TeakOpenSettingsAppToThisAppsSettings(void) {
  return [[Teak sharedInstance] openSettingsAppToThisAppsSettings];
}

BOOL TeakCanOpenSettingsAppToThisAppsSettings(void) {
  return [[Teak sharedInstance] canOpenSettingsAppToThisAppsSettings];
}

BOOL TeakCanOpenNotificationSettings(void) {
  return [[Teak sharedInstance] canOpenNotificationSettings];
}

BOOL TeakOpenNotificationSettings(void) {
  return [[Teak sharedInstance] openNotificationSettings];
}

int TeakGetNotificationState(void) {
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

const char* TeakGetAppConfiguration(void) {
  return [[[Teak sharedInstance] getAppConfiguration] UTF8String];
}

const char* TeakGetDeviceConfiguration(void) {
  return [[[Teak sharedInstance] getDeviceConfiguration] UTF8String];
}

void TeakReportTestException(void) {
  [[Teak sharedInstance] reportTestException];
}

void TeakSetLogListener(TeakLogListener listener) {
  [[Teak sharedInstance] setLogListener:listener];
}

BOOL TeakHandleDeepLinkPath(const char* pathAsCStr) {
  NSString* path = [NSString stringWithUTF8String:pathAsCStr];
  return [[Teak sharedInstance] handleDeepLinkPath:path];
}

BOOL TeakRequestPushAuthorizationWithCallback(BOOL includeProvisional, void (*callback)(void*, BOOL, NSError*), void* context) {
  UIApplication* application = [UIApplication sharedApplication];

  // If provisional auth is requested, but this is not iOS 12+, bail out and return NO
  if (includeProvisional) {
    if (@available(iOS 12.0, *)) {
      // The @available syntactic sugar does not allow negation
    } else {
      if (callback != nil) {
        callback(context, NO, [NSError errorWithDomain:@"teak" code:1 userInfo:@{@"description" : @"Provisional notifications requested but not supported"}]);
      }
      return NO;
    }
  }

  // The following code registers for push notifications in both an iOS 8 and iOS 9+ friendly way
  if (NSClassFromString(@"UNUserNotificationCenter") != nil) {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    UNAuthorizationOptions authOptions = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
    if (@available(iOS 12.0, *)) {
      if (includeProvisional) { // the @available syntactic sugar is odd, so I have to do this nested if
        authOptions |= UNAuthorizationOptionProvisional;
      }
    }
    [center requestAuthorizationWithOptions:authOptions
                          completionHandler:^(BOOL granted, NSError* _Nullable error) {
                            if (granted) {
                              dispatch_async(dispatch_get_main_queue(), ^{
                                [application registerForRemoteNotifications];
                              });
                            }

                            if (callback != nil) {
                              callback(context, granted, error);
                            }
                          }];
    return YES;
  } else if ([application respondsToSelector:@selector(registerUserNotificationSettings:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIUserNotificationSettings* settings = [UIUserNotificationSettings settingsForTypes:(UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound) categories:nil];
    [application registerUserNotificationSettings:settings];
#pragma clang diagnostic pop
    if (callback != nil) {
      callback(context, NO, [NSError errorWithDomain:@"teak" code:0 userInfo:@{@"description" : @"Deprecated version of iOS, callbacks not supported for this function."}]);
    }
    return YES;
  } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIRemoteNotificationType myTypes = UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeAlert | UIRemoteNotificationTypeSound;
    [application registerForRemoteNotificationTypes:myTypes];
#pragma clang diagnostic pop
    if (callback != nil) {
      callback(context, NO, [NSError errorWithDomain:@"teak" code:0 userInfo:@{@"description" : @"Deprecated version of iOS, callbacks not supported for this function."}]);
    }
    return YES;
  }

  // Should never get here
  return NO;
}

BOOL TeakRequestPushAuthorization(BOOL includeProvisional) {
  return TeakRequestPushAuthorizationWithCallback(includeProvisional, NULL, NULL);
}

TeakOperation* TeakSetStateForChannel(const char* stateCstr, const char* channelCstr) {
  NSString* state = [NSString stringWithUTF8String:stateCstr];
  NSString* channel = [NSString stringWithUTF8String:channelCstr];
  return [[Teak sharedInstance] setState:state forChannel:channel];
}

TeakOperation* TeakSetStateForCategory(const char* stateCstr, const char* channelCstr, const char* categoryCstr) {
  NSString* state = [NSString stringWithUTF8String:stateCstr];
  NSString* channel = [NSString stringWithUTF8String:channelCstr];
  NSString* category = [NSString stringWithUTF8String:categoryCstr];
  return [[Teak sharedInstance] setState:state forChannel:channel andCategory:category];
}

NSDictionary* TeakOperationGetResultAsDictionary(TeakOperation* operation) {
  return [[operation result] toDictionary];
}

void TeakAddOperationToQueue(NSOperation* op) {
  [[Teak sharedInstance].operationQueue addOperation:op];
}
