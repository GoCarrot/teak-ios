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

#import <Foundation/Foundation.h>

@class TeakAppConfiguration;

@interface TeakDeviceConfiguration : NSObject
@property (strong, nonatomic, readonly) NSString* _Nonnull deviceId;
@property (strong, nonatomic, readonly) NSString* _Nonnull deviceModel;
@property (strong, nonatomic, readonly) NSString* _Nullable pushToken;
@property (strong, nonatomic, readonly) NSString* _Nonnull platformString;
@property (strong, nonatomic, readonly) NSString* _Nullable advertisingIdentifier;
@property (nonatomic, readonly) BOOL limitAdTracking;

- (nullable id)initWithAppConfiguration:(nonnull TeakAppConfiguration*)appConfiguration;
- (nonnull NSDictionary*)to_h;
- (void)assignPushToken:(nonnull NSString*)pushToken;
@end
