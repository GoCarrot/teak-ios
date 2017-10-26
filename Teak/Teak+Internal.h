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

#import "TeakLog.h"
#import "TeakRaven.h"

@class TeakDebugConfiguration;
@class TeakAppConfiguration;
@class TeakDeviceConfiguration;
@class TeakCore;

@interface Teak ()
@property (nonatomic, readwrite) BOOL enableDebugOutput;

@property (strong, nonatomic) TeakDebugConfiguration* _Nonnull debugConfiguration;
@property (strong, nonatomic) TeakAppConfiguration* _Nonnull appConfiguration;
@property (strong, nonatomic) TeakDeviceConfiguration* _Nonnull deviceConfiguration;

@property (strong, nonatomic, readwrite) NSString* _Nonnull sdkVersion;

@property (strong, nonatomic) NSString* _Nullable fbAccessToken;

@property (strong, nonatomic) TeakRaven* _Nonnull sdkRaven;

@property (strong, nonatomic) NSOperationQueue* _Nonnull operationQueue;
@property (strong, nonatomic) NSOperation* _Nonnull waitForDeepLinkOperation;

@property (strong, nonatomic) TeakLog* _Nonnull log;

@property (strong, nonatomic) TeakCore* _Nonnull core;

// Static initialization time or main()
- (id _Nullable)initWithApplicationId:(NSString* _Nonnull)appId andSecret:(NSString* _Nonnull)appSecret;

+ (NSURLSession* _Nonnull)sharedURLSession;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnullability-completeness"
// App launch
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions;

// Post-launch lifecycle
- (void)applicationDidBecomeActive:(UIApplication*)application;
- (void)applicationWillResignActive:(UIApplication*)application;

// Deep Linking
- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation;
- (BOOL)application:(UIApplication*)application continueUserActivity:(NSUserActivity*)userActivity restorationHandler:(void (^)(NSArray* _Nullable))restorationHandler;

// Push notification
- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken;
- (void)application:(UIApplication*)application didRegisterUserNotificationSettings:(UIUserNotificationSettings*)notificationSettings;
- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error;
- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo;
#pragma clang diagnostic pop

@end
