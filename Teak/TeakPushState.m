/* Teak -- Copyright (C) 2018 GoCarrot Inc.
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

#import "TeakPushState.h"
#import <UserNotifications/UNNotificationSettings.h>
#import <UserNotifications/UNUserNotificationCenter.h>

#ifndef __IPHONE_12_0
#define __IPHONE_12_0 120000
#endif

@implementation TeakPushState

DefineTeakState(Unknown, (@[ @"Provisional", @"Authorized", @"Denied" ]));
DefineTeakState(Provisional, (@[ @"Authorized", @"Denied" ]));
DefineTeakState(Authorized, (@[ @"Denied" ]));
DefineTeakState(Denied, (@[ @"Authorized" ]));

- (TeakPushState*)init {
  self = [super init];
  if (self) {
    [TeakEvent addEventHandler:self];
  }
  return self;
}

- (void)handleEvent:(TeakEvent*)event {
}

+ (void)determineCurrentPushState:(void (^)(TeakState* pushState))completionBlock {
  if (NSClassFromString(@"UNUserNotificationCenter") != nil) {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* _Nonnull settings) {
      TeakState* pushState = [TeakPushState Unknown];

      switch (settings.authorizationStatus) {
        case UNAuthorizationStatusDenied: {
          pushState = [TeakPushState Denied];
        } break;
        case UNAuthorizationStatusAuthorized: {
          pushState = [TeakPushState Authorized];
        } break;
        case UNAuthorizationStatusNotDetermined: {
          // Keep as Unknown
        } break;
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_12_0
        case UNAuthorizationStatusProvisional: {
          pushState = [TeakPushState Provisional];
        } break;
#endif
      }

      // Inform caller
      if (completionBlock != nil) {
        completionBlock(pushState);
      }
    }];
  } else if (completionBlock != nil) {
    BOOL pushEnabled = [TeakPushState applicationHasRemoteNotificationsEnabled:[UIApplication sharedApplication]];
    completionBlock(pushEnabled ? [TeakPushState Authorized] : [TeakPushState Denied]);
  }
}

+ (BOOL)applicationHasRemoteNotificationsEnabled:(UIApplication*)application {
  BOOL pushEnabled = NO;
  if ([application respondsToSelector:@selector(isRegisteredForRemoteNotifications)]) {
    pushEnabled = [application isRegisteredForRemoteNotifications];
  } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIRemoteNotificationType types = [application enabledRemoteNotificationTypes];
    pushEnabled = types & UIRemoteNotificationTypeAlert;
#pragma clang diagnostic pop
  }
  return pushEnabled;
}

@end
