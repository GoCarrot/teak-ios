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

#import "TeakEvent.h"
#import <Foundation/Foundation.h>

extern NSString* _Nonnull const TeakDeviceConfiguration_NotificationDisplayState_Enabled;
extern NSString* _Nonnull const TeakDeviceConfiguration_NotificationDisplayState_Disabled;
extern NSString* _Nonnull const TeakDeviceConfiguration_NotificationDisplayState_NotDetermined;

@class TeakAppConfiguration;

@interface TeakDeviceConfiguration : NSObject <TeakEventHandler>
@property (strong, nonatomic, readonly) NSString* _Nonnull deviceId;
@property (strong, nonatomic, readonly) NSString* _Nonnull deviceModel;
@property (strong, nonatomic, readonly) NSString* _Nonnull pushToken;
@property (strong, nonatomic, readonly) NSString* _Nonnull platformString;
@property (strong, nonatomic, readonly) NSString* _Nonnull advertisingIdentifier;
@property (strong, nonatomic, readonly) NSString* _Nonnull notificationDisplayEnabled;
@property (nonatomic, readonly) BOOL limitAdTracking;

- (nullable id)init;
- (nonnull NSDictionary*)to_h;
@end
