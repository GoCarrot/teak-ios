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

typedef void (^TeakRequestResponse)(NSURLResponse* response, NSDictionary* reply);

@interface TeakRequest : NSObject <NSURLSessionTaskDelegate, NSURLSessionDataDelegate>
@property (strong, nonatomic, readonly) NSString* endpoint;
@property (strong, nonatomic, readonly) NSDictionary* payload;
@property (strong, nonatomic, readonly) TeakRequestResponse callback;

- (TeakRequest*)initWithSession:(nonnull TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(TeakRequestResponse)callback;
- (void)send;
@end
