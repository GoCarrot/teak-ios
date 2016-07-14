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

#import <UIKit/UIKit.h>
#import "TeakState.h"

@class TeakSession;
@class TeakAppConfiguration;
@class TeakDeviceConfiguration;
@class TeakRemoteConfiguration;

typedef void (^UserIdReadyBlock)(TeakSession*);

@interface TeakSession : NSObject
@property (strong, nonatomic, readonly) TeakAppConfiguration* appConfiguration;
@property (strong, nonatomic, readonly) TeakDeviceConfiguration* deviceConfiguration;
@property (strong, nonatomic, readonly) TeakRemoteConfiguration* remoteConfiguration;
@property (strong, nonatomic, readonly) NSString* userId;

DeclareTeakState(Created);
DeclareTeakState(Configured);
DeclareTeakState(UserIdentified);
DeclareTeakState(Expiring);
DeclareTeakState(Expired);

+ (void)whenUserIdIsReadyRun:(nonnull UserIdReadyBlock)block;

+ (void)setUserId:(NSString*)userId;
+ (void)didLaunchFromTeakNotification:(nonnull NSString*)teakNotifId appConfiguration:(nonnull TeakAppConfiguration*)appConfiguration deviceConfiguration:(nonnull TeakDeviceConfiguration*)deviceConfiguration;
+ (void)didLaunchFromDeepLink:(nonnull NSString*)deepLink appConfiguration:(nonnull TeakAppConfiguration*)appConfiguration deviceConfiguration:(nonnull TeakDeviceConfiguration*)deviceConfiguration;

+ (void)applicationWillEnterForeground:(UIApplication*)application appConfiguration:(nonnull TeakAppConfiguration*)appConfiguration deviceConfiguration:(nonnull TeakDeviceConfiguration*)deviceConfiguration;
+ (void)applicationWillResignActive:(UIApplication*)application appConfiguration:(nonnull TeakAppConfiguration*)appConfiguration deviceConfiguration:(nonnull TeakDeviceConfiguration*)deviceConfiguration;
@end
