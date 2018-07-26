/* Teak Example -- Copyright (C) 2016 GoCarrot Inc.
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

#import "AppDelegate.h"
#import <UserNotifications/UserNotifications.h>
#import <sys/utsname.h>

// Step 3:
// Import Teak into your UIApplicationDelegate implementation.
#import <Teak/Teak.h>

// For testing
extern BOOL TeakLink_HandleDeepLink(NSURL* deepLink);

@import AdSupport;

@interface AppDelegate ()

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  [TeakLink registerRoute:@"/test/:data"
                     name:@"Store SKU"
              description:@"Will open the In App Purchase for the specified SKU"
                    block:^(NSDictionary* _Nonnull parameters) {
                      NSLog(@"%@", parameters);
                    }];

  // Register a deep link that opens the store to the specific SKU
  // Routes use pattern matching to capture variables. Variables are prefixed with ':', so ':sku' will create
  //    a key named 'sku' in the dictionary passed to the block.
  // Name and Description are optional, but will show up in the Teak Dashboard to help identify the deep link
  [TeakLink registerRoute:@"/store/:sku"
                     name:@"Store SKU"
              description:@"Will open the In App Purchase for the specified SKU"
                    block:^(NSDictionary* _Nonnull parameters) {
                      NSLog(@"%@", parameters);
                      NSLog(@"IT CALLED THE THING!! SKU: %@", parameters[@"sku"]);
                    }];

  // In your game, you will want to use the same user id that you use in your database.
  //
  // These user ids should be unique, no two players should have the same user id.
  struct utsname systemInfo;
  uname(&systemInfo);
  NSString* userId = [NSString stringWithFormat:@"native-%@", [[NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding] lowercaseString]];

  // Step 4:
  // Call identifyUser as soon as you know the user id of the current player.
  [[Teak sharedInstance] identifyUser:userId];

  // Step 5:
  // Tell Teak that you want to be notified when your game has been launched via a Push Notification.
  //
  // See the bottom of this file for an example of a handler function.
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleTeakNotification:)
                                               name:TeakNotificationAppLaunch
                                             object:nil];

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleTeakReward:)
                                               name:TeakOnReward
                                             object:nil];

  // The following code registers for push notifications in both an iOS 8 and iOS 9+ friendly way
  if (NSClassFromString(@"UNUserNotificationCenter") != nil) {
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    UNAuthorizationOptions authOptions = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
    if (@available(iOS 12.0, *)) {
      //authOptions |= UNAuthorizationOptionProvisional;
    }
    [center requestAuthorizationWithOptions:authOptions
                          completionHandler:^(BOOL granted, NSError* _Nullable error) {
                            if (granted) {
                              dispatch_async(dispatch_get_main_queue(), ^{
                                [application registerForRemoteNotifications];
                              });
                            }
                          }];
  } else if ([application respondsToSelector:@selector(registerUserNotificationSettings:)]) {
    UIUserNotificationSettings* settings = [UIUserNotificationSettings settingsForTypes:(UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound) categories:nil];
    [application registerUserNotificationSettings:settings];
  } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIRemoteNotificationType myTypes = UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeAlert | UIRemoteNotificationTypeSound;
    [application registerForRemoteNotificationTypes:myTypes];
#pragma clang diagnostic pop
  }

  return YES;
}

- (void)application:(UIApplication*)application didRegisterUserNotificationSettings:(UIUserNotificationSettings*)notificationSettings {
  // Register to receive notifications
  [application registerForRemoteNotifications];
}

// This is an example of a handler function that will be called when your app
// is launched from a Push Notification.
- (void)handleTeakNotification:(NSNotification*)notification {
  NSLog(@"TEAK TOLD US ABOUT A NOTIFICATION, THANKS TEAK!");
}

- (void)handleTeakReward:(NSNotification*)notification {
  NSDictionary* userInfo = notification.userInfo;
  NSLog(@"%@", userInfo);
#ifdef SAMPLE_ALERT_ON_REWARD
  NSDictionary* reward = userInfo[@"reward"];
  if (reward) {
    dispatch_async(dispatch_get_main_queue(), ^{
      NSNumber* coins = reward[@"coins"];
      UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Sweet Coins!"
                                                                     message:[NSString stringWithFormat:@"You just got %@ coins!", coins]
                                                              preferredStyle:UIAlertControllerStyleAlert];

      UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"Awesome"
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(UIAlertAction* action){}];

      [alert addAction:defaultAction];
      [[[[UIApplication sharedApplication] keyWindow] rootViewController] presentViewController:alert animated:YES completion:nil];
    });
  }
#endif
}

// This is for our automated testing.
extern NSTimeInterval TeakSameSessionDeltaSeconds;
- (NSString*)integrationTestTimeout:(NSString*)timeout {
  TeakSameSessionDeltaSeconds = [timeout doubleValue];
  NSLog(@"TeakSameSessionDeltaSeconds = %f", TeakSameSessionDeltaSeconds);
  return nil;
}

- (NSString*)integrationTestSchedulePush:(NSString*)message {
  TeakNotification* notif = [TeakNotification scheduleNotificationForCreative:@"calabash_test" withMessage:message secondsFromNow:1];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    while (notif.completed == NO) {
      sleep(1);
    }
    NSLog(@"Notification scheduled: %@", notif.teakNotifId);
  });
  return nil;
}

@end
