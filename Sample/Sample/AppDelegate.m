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

// This is a C helper for requesting push permissions
extern BOOL TeakRequestPushAuthorization(BOOL includeProvisional);

#define SAMPLE_ALERT_ON_REWARD 1

// Step 3:
// Import Teak into your UIApplicationDelegate implementation.
#import <Teak/Teak.h>

@import AdSupport;

@interface AppDelegate () <UNUserNotificationCenterDelegate>

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
  center.delegate = self;
  [center setNotificationCategories:[[NSSet alloc] init]]; // This is intentional empty set

  [TeakLink registerRoute:@"/test/:data"
                     name:@"Test"
              description:@"Echo to log"
                    block:^(NSDictionary* _Nonnull parameters) {
                      NSLog(@"%@", parameters);
                    }];

  [TeakLink registerRoute:@"/slots/:slot"
                     name:@"Test"
              description:@"Echo to log"
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
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleTeakPostLaunchSummary:)
                                               name:TeakPostLaunchSummary
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleTeakLaunchedFromLink:)
                                               name:TeakLaunchedFromLink
                                             object:nil];

  // Request push permissions via the Unity helper
  TeakRequestPushAuthorization(NO);

  // Test event
  [[Teak sharedInstance] trackEventWithActionId:@"Player_Level_Up" forObjectTypeId:nil andObjectInstanceId:nil];

  return YES;
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (void)application:(UIApplication*)application didRegisterUserNotificationSettings:(UIUserNotificationSettings*)notificationSettings {
  // Register to receive notifications
  [application registerForRemoteNotifications];
}
#pragma clang diagnostic pop

- (BOOL)application:(UIApplication*)app openURL:(NSURL*)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id>*)options {
  return YES;
}

// This is an example of a handler function that will be called when your app
// is launched from a Push Notification.
- (void)handleTeakNotification:(NSNotification*)notification {
  NSDictionary* userInfo = notification.userInfo;
  NSLog(@"handleTeakNotification: %@", userInfo);
}

- (void)handleTeakReward:(NSNotification*)notification {
  NSDictionary* userInfo = notification.userInfo;
  NSLog(@"handleTeakReward: %@", userInfo);
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

- (void)handleTeakPostLaunchSummary:(NSNotification*)notification {
  NSDictionary* userInfo = notification.userInfo;
  NSLog(@"handleTeakPostLaunchSummary: %@", userInfo);
}

- (void)handleTeakLaunchedFromLink:(NSNotification*)notification {
  NSDictionary* userInfo = notification.userInfo;
  NSLog(@"handleTeakLaunchedFromLink: %@", userInfo);
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

- (void)userNotificationCenter:(UNUserNotificationCenter*)center
       willPresentNotification:(UNNotification*)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
  if (![Teak willPresentNotification:notification withCompletionHandler:completionHandler]) {
    // Perform your processing
    completionHandler(UNNotificationPresentationOptionAlert);
  }
}

- (void)userNotificationCenter:(UNUserNotificationCenter*)center
    didReceiveNotificationResponse:(UNNotificationResponse*)response
             withCompletionHandler:(void (^)(void))completionHandler {
  if (![Teak didReceiveNotificationResponse:response withCompletionHandler:completionHandler]) {
    // Perform your processing
    completionHandler();
  }
}

@end
