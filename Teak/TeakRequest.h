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

typedef void (^TeakRequestResponse)(NSURLResponse* _Nonnull response, NSDictionary* _Nonnull reply);

@interface TeakRequest : NSObject <NSURLSessionTaskDelegate, NSURLSessionDataDelegate>
@property (strong, nonatomic, readonly) NSString* _Nonnull endpoint;
@property (strong, nonatomic, readonly) NSDictionary* _Nonnull payload;
@property (copy, nonatomic, readonly) TeakRequestResponse _Nullable callback;

- (nullable TeakRequest*)initWithSession:(nonnull TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(nullable TeakRequestResponse)callback;
- (nullable TeakRequest*)initWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(nullable TeakRequestResponse)callback;

- (void)send;
@end
