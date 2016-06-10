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

@class TeakCache;
@class TeakRequestThread;

#define kTeakServicesHostname @"services.gocarrot.com"
#define kDefaultHostUrlScheme @"https"
#define kMergeLastSessionDeltaSeconds 120

extern NSString* URLEscapedString(NSString* inString);

@interface Teak ()

@property (strong, nonatomic) NSString* appId;
@property (strong, nonatomic) NSString* appSecret;
@property (strong, nonatomic) NSString* pushToken;
@property (strong, nonatomic) NSString* userId;
@property (strong, nonatomic) NSString* sdkVersion;
@property (strong, nonatomic) NSString* sdkPlatform;
@property (strong, nonatomic) NSString* appVersion;
@property (strong, nonatomic) NSNumber* advertisingTrackingLimited;
@property (strong, nonatomic) NSString* advertisingIdentifier;
@property (strong, nonatomic) NSString* launchedFromTeakNotifId;
@property (strong, nonatomic) NSURL* launchedFromDeepLink;
@property (strong, nonatomic) NSString* deviceModel;
@property (strong, nonatomic) NSString* fbAccessToken;
@property (strong, nonatomic) NSString* teakCountryCode;

@property (strong, nonatomic) NSDate*   lastSessionEndedAt;

@property (strong, nonatomic) NSString* hostname;

@property (strong, nonatomic) NSString*  dataPath;
@property (strong, nonatomic) TeakCache* cache;
@property (strong, nonatomic) TeakRequestThread* requestThread;
@property (atomic)            BOOL       userIdentifiedThisSession;
@property (atomic)            BOOL       isProduction;

@property (strong, nonatomic) NSOperationQueue* dependentOperationQueue;
@property (strong, nonatomic) NSOperation* serviceConfigurationOperation;
@property (strong, nonatomic) NSOperation* userIdOperation;
@property (strong, nonatomic) NSOperation* liveConnectionOperation;
@property (strong, nonatomic) NSOperation* identifyUserOperation;
@property (strong, nonatomic) NSOperation* facebookAccessTokenOperation;
@property (strong, nonatomic) NSOperation* pushTokenOperation;

- (BOOL)handleOpenURL:(NSURL*)url;
- (void)applicationDidBecomeActive:(UIApplication*)application;
- (void)applicationWillResignActive:(UIApplication*)application;
- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken;
- (void)application:(UIApplication*)application didRegisterUserNotificationSettings:(UIUserNotificationSettings*)notificationSettings;
- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error;
- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo;
- (BOOL)application:(UIApplication*)application willFinishLaunchingWithOptions:(NSDictionary*)launchOptions;
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions;

@end
