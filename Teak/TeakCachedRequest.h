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
#import "TeakRequest.h"
#import "TeakCache.h"

@interface TeakCachedRequest : TeakRequest

@property (strong, nonatomic, readonly) NSString* requestId;
@property (strong, nonatomic, readonly) NSDate* dateIssued;
@property (nonatomic, readonly) NSUInteger retryCount;
@property (nonatomic, readonly) sqlite3_uint64 cacheId;

+ (id)requestForService:(TeakRequestServiceType)serviceType atEndpoint:(NSString*)endpoint withPayload:(NSDictionary*)payload inCache:(TeakCache*)cache callback:(TeakRequestResponse)callback;
- (id)initForService:(TeakRequestServiceType)serviceType atEndpoint:(NSString*)endpoint payload:(NSDictionary*)payload requestId:(NSString*)requestId dateIssued:(NSDate*)dateIssued cacheId:(sqlite3_uint64)cacheId retryCount:(NSUInteger)retryCount callback:(TeakRequestResponse)callback;

- (NSString*)description;

@end
