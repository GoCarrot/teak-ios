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
#import "TeakCache.h"
#import "TeakRequest.h"

@class Teak;

@interface TeakRequestThread : NSObject

@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic) NSUInteger maxRetryCount; // 0 = infinite
@property (strong, nonatomic, readonly) TeakCache* cache;

- (id)initWithTeak:(Teak*)teak;

- (BOOL)addRequestForService:(TeakRequestServiceType)serviceType atEndpoint:(NSString*)endpoint usingMethod:(NSString*)method withPayload:(NSDictionary*)payload;
- (BOOL)addRequestForService:(TeakRequestServiceType)serviceType atEndpoint:(NSString*)endpoint  usingMethod:(NSString*)method withPayload:(NSDictionary*)payload callback:(TeakRequestResponse)callback;
- (BOOL)addRequestForService:(TeakRequestServiceType)serviceType atEndpoint:(NSString*)endpoint  usingMethod:(NSString*)method withPayload:(NSDictionary*)payload callback:(TeakRequestResponse)callback atFront:(BOOL)atFront;

- (void)start;
- (void)stop;
- (void)signal;
- (void)processRequest:(TeakRequest*)request;

- (void)addRequestInQueue:(TeakRequest*)request atFront:(BOOL)atFront;

@end
