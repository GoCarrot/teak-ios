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

@class TeakRequest;
@class TeakSession;

typedef void (^TeakRequestResponse)(NSDictionary* _Nonnull reply);

@interface TeakBatchConfiguration : NSObject
@property (nonatomic) float time;
@property (nonatomic) long count;
@end

@interface TeakRetryConfiguration : NSObject
@property (nonatomic) float jitter;
@property (strong, nonatomic) NSArray* _Nonnull times;
@property (nonatomic) NSUInteger retryIndex;
@end

@interface TeakRequest : NSObject
@property (strong, nonatomic, readonly) NSString* _Nonnull endpoint;
@property (strong, nonatomic, readonly) NSDictionary* _Nonnull payload;
@property (copy, nonatomic, readonly) TeakRequestResponse _Nullable callback;

@property (strong, nonatomic, readonly) TeakBatchConfiguration* _Nonnull batch;
@property (strong, nonatomic, readonly) TeakRetryConfiguration* _Nonnull retry;
@property (nonatomic, readonly) BOOL blackhole;

+ (nullable TeakRequest*)requestWithSession:(nonnull TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(nullable TeakRequestResponse)callback;
+ (nullable TeakRequest*)requestWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(nullable TeakRequestResponse)callback;
- (nullable TeakRequest*)initWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(nullable TeakRequestResponse)callback addCommonPayload:(BOOL)addCommonToPayload;

- (void)send;
- (NSDictionary* _Nonnull)to_h;
@end
