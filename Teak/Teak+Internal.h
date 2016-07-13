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

@class TeakCache;
@class TeakRequestThread;

@interface Teak ()
@property (nonatomic, readwrite) BOOL enableDebugOutput;

@property (strong, nonatomic) TeakDebugConfiguration* debugConfiguration;
@property (strong, nonatomic) TeakAppConfiguration* appConfiguration;
@property (strong, nonatomic) TeakDeviceConfiguration* deviceConfiguration;

@property (strong, nonatomic, readwrite) NSString* sdkVersion;

@property (strong, nonatomic) NSString* fbAccessToken;

@property (strong, nonatomic) TeakCache* cache;
@property (strong, nonatomic) TeakRequestThread* requestThread;

@property (strong, nonatomic) NSOperationQueue* dependentOperationQueue;
@property (strong, nonatomic) NSOperation* facebookAccessTokenOperation;

@property (strong, nonatomic) NSMutableDictionary* priceInfoDictionary;
@property (strong, atomic)    NSMutableDictionary* priceInfoCompleteDictionary;

@property (strong, nonatomic) TeakRaven* sdkRaven;

- (id)initWithApplicationId:(NSString*)appId andSecret:(NSString*)appSecret;

- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation;
- (void)applicationWillEnterForeground:(UIApplication*)application;
- (void)applicationWillResignActive:(UIApplication*)application;
- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken;
- (void)application:(UIApplication*)application didRegisterUserNotificationSettings:(UIUserNotificationSettings*)notificationSettings;
- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error;
- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo;
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions;

@end
