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

#import "TeakState.h"
#import <UIKit/UIKit.h>

@class TeakSession;
@class TeakAppConfiguration;
@class TeakDeviceConfiguration;
@class TeakRemoteConfiguration;

typedef void (^UserIdReadyBlock)(TeakSession* _Nonnull);

@interface TeakSession : NSObject
@property (strong, nonatomic, readonly) TeakAppConfiguration* _Nonnull appConfiguration;
@property (strong, nonatomic, readonly) TeakDeviceConfiguration* _Nonnull deviceConfiguration;
@property (strong, nonatomic, readonly) TeakRemoteConfiguration* _Nonnull remoteConfiguration;
@property (strong, nonatomic, readonly) NSString* _Nullable userId;
@property (strong, nonatomic, readonly) NSString* _Nonnull sessionId;

DeclareTeakState(Created);
DeclareTeakState(Configured);
DeclareTeakState(IdentifyingUser);
DeclareTeakState(UserIdentified);
DeclareTeakState(Expiring);
DeclareTeakState(Expired);

+ (void)registerStaticEventListeners;

+ (void)whenUserIdIsReadyRun:(nonnull UserIdReadyBlock)block;
+ (void)whenUserIdIsOrWasReadyRun:(nonnull UserIdReadyBlock)block;

+ (void)didLaunchFromTeakNotification:(nonnull NSString*)teakNotifId appConfiguration:(nonnull TeakAppConfiguration*)appConfiguration deviceConfiguration:(nonnull TeakDeviceConfiguration*)deviceConfiguration;
+ (void)didLaunchFromDeepLink:(nonnull NSString*)deepLink appConfiguration:(nonnull TeakAppConfiguration*)appConfiguration deviceConfiguration:(nonnull TeakDeviceConfiguration*)deviceConfiguration;

+ (void)applicationWillResignActive:(nonnull UIApplication*)application appConfiguration:(nonnull TeakAppConfiguration*)appConfiguration deviceConfiguration:(nonnull TeakDeviceConfiguration*)deviceConfiguration;
@end
