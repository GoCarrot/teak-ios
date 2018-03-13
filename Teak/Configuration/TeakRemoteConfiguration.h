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
@class TeakSession;

@interface TeakRemoteConfiguration : NSObject
@property (strong, nonatomic, readonly) NSString* _Nonnull hostname;
@property (strong, nonatomic, readonly) NSString* _Nullable sdkSentryDsn;
@property (strong, nonatomic, readonly) NSString* _Nullable appSentryDsn;
@property (strong, nonatomic, readonly) NSDictionary* _Nonnull batching;

- (TeakRemoteConfiguration* _Nullable)initForSession:(TeakSession* _Nonnull)session;
- (nonnull NSDictionary*)to_h;
@end
