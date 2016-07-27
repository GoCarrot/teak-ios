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

#import <Teak/Teak.h>

#import "TeakRaven.h"

@class TeakDebugConfiguration;
@class TeakAppConfiguration;
@class TeakDeviceConfiguration;

@interface Teak ()
@property (nonatomic, readwrite) BOOL enableDebugOutput;

@property (strong, nonatomic) TeakDebugConfiguration* debugConfiguration;
@property (strong, nonatomic) TeakAppConfiguration* appConfiguration;
@property (strong, nonatomic) TeakDeviceConfiguration* deviceConfiguration;

@property (strong, nonatomic, readwrite) NSString* sdkVersion;

@property (strong, nonatomic) NSString* fbAccessToken;

@property (strong, nonatomic) TeakRaven* sdkRaven;

// Static initialization time or main()
- (id)initWithApplicationId:(NSString*)appId andSecret:(NSString*)appSecret;

// App launch
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions;

// Post-launch lifecycle
- (void)applicationDidBecomeActive:(UIApplication*)application;
- (void)applicationWillResignActive:(UIApplication*)application;

// Deep Linking
- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation;

// Push notification
- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken;
- (void)application:(UIApplication*)application didRegisterUserNotificationSettings:(UIUserNotificationSettings*)notificationSettings;
- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error;
- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo;

@end
