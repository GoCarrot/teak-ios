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

@class TeakDeviceConfiguration;
@class TeakAppConfiguration;
@class TeakRemoteConfiguration;

@interface TeakLog : NSObject
- (void)useSdk:(nonnull NSDictionary*)sdkVersion;
- (void)useDeviceConfiguration:(nonnull TeakDeviceConfiguration*)deviceConfiguration;
- (void)useAppConfiguration:(nonnull TeakAppConfiguration*)appConfiguration;
- (void)useRemoteConfiguration:(nonnull TeakRemoteConfiguration*)remoteConfiguration;
- (void)logEvent:(nonnull NSString*)eventType level:(nonnull NSString*)logLevel eventData:(nullable NSDictionary*)eventData;
@end

extern __attribute__((overloadable)) void TeakLog_e(NSString* _Nonnull eventType);
extern __attribute__((overloadable)) void TeakLog_e(NSString* _Nonnull eventType, NSDictionary* _Nullable eventData);
extern __attribute__((overloadable)) void TeakLog_e(NSString* _Nonnull eventType, NSString* _Nullable message);
extern __attribute__((overloadable)) void TeakLog_e(NSString* _Nonnull eventType, NSString* _Nullable message, NSDictionary* _Nullable eventData);

extern __attribute__((overloadable)) void TeakLog_i(NSString* _Nonnull eventType);
extern __attribute__((overloadable)) void TeakLog_i(NSString* _Nonnull eventType, NSDictionary* _Nullable eventData);
extern __attribute__((overloadable)) void TeakLog_i(NSString* _Nonnull eventType, NSString* _Nullable message);
extern __attribute__((overloadable)) void TeakLog_i(NSString* _Nonnull eventType, NSString* _Nullable message, NSDictionary* _Nullable eventData);
