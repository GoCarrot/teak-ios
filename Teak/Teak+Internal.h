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

#define kTeakServicesHostname @"services.gocarrot.com"
#define kDefaultHostUrlScheme @"https"

extern NSString* const TeakServicesConfiguredNotification;
extern NSString* const TeakPushTokenReceived;
extern NSString* const TeakUserIdAvailableNotification;
extern NSString* const TeakAccessTokenAvailableNotification;

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
@property (strong, nonatomic) NSString* fbAccessToken;
@property (strong, nonatomic) NSString* sessionId;

@property (strong, nonatomic) NSString*  dataPath;
@property (strong, nonatomic) TeakCache* cache;
@property (atomic)            BOOL       userIdentifiedThisSession;

- (BOOL)handleOpenURL:(NSURL*)url;
- (void)beginApplicationSession:(UIApplication*)application;
- (void)endApplicationSession:(UIApplication*)application;
- (void)setDevicePushToken:(NSData*)deviceToken;
- (BOOL)application:(UIApplication*)application willFinishLaunchingWithOptions:(NSDictionary*)launchOptions;

@end
