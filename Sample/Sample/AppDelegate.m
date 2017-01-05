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

// Step 3:
// Import Teak into your UIApplicationDelegate implementation.
#import <Teak/Teak.h>

@import AdSupport;

@interface AppDelegate ()

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
   // For this example, we are simply using the IDFA for a user id. In your game, you will
   // want to use the same user id that you use in your database.
   //
   // These user ids should be unique, no two players should have the same user id.
   NSString* userId = [[ASIdentifierManager sharedManager].advertisingIdentifier UUIDString];

   // Step 3:
   // Call identifyUser as soon as you know the user id of the current player.
   [[Teak sharedInstance] identifyUser:userId];

   // Step 4:
   // Tell Teak that you want to be notified when your game has been launched via a Push Notification.
   //
   // See the bottom of this file for an example of a handler function.
   [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(handleTeakNotification:)
                                                name:TeakNotificationAppLaunch
                                              object:nil];

   // The following code registers for push notifications in both an iOS 8 and iOS 9+ friendly way
   if ([application respondsToSelector:@selector(registerUserNotificationSettings:)]) {
      UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:(UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound) categories:nil];
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

- (void)application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings
{
   // Register to receive notifications
   [application registerForRemoteNotifications];
}

// This is an example of a handler function that will be called when your app
// is launched from a Push Notification.
- (void)handleTeakNotification:(NSNotification*)notification
{
   // If the notification contains a reward, it will be found in the 'teakReward' key of the user info dictionary.
   NSDictionary* teakReward = [notification.userInfo objectForKey:@"teakReward"];

   // If the notification contains a deep link, the path of the link will be found in the 'teakDeepLinkPath' of the user info dictionary.
   NSDictionary* teakDeepLinkPath = [notification.userInfo objectForKey:@"teakDeepLinkPath"];
   NSDictionary* teakDeepLinkQueryParameters = [notification.userInfo objectForKey:@"teakDeepLinkQueryParameters"];

   NSLog(@"TEAK TOLD US ABOUT A NOTIFICATION, THANKS TEAK!\n%@\n%@\n%@", teakReward, teakDeepLinkPath, teakDeepLinkQueryParameters);
}

@end
