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
#include <sqlite3.h>

typedef enum {
   TeakRequestServiceAuth    = -2,
   TeakRequestServiceMetrics = -1,
   TeakRequestServicePost    = 2
} TeakRequestServiceType;

@class TeakRequestThread;
@class TeakRequest;

typedef void (^TeakRequestResponse)(TeakRequest* request, NSHTTPURLResponse* response, NSData* data, TeakRequestThread* requestThread);

extern NSString* const TeakRequestTypePOST;

@interface TeakRequest : NSObject

@property (nonatomic, readonly) TeakRequestServiceType serviceType;
@property (strong, nonatomic, readonly) NSString* endpoint;
@property (strong, nonatomic, readonly) NSDictionary* payload;
@property (strong, nonatomic, readonly) NSString* method;
@property (strong, nonatomic, readonly) TeakRequestResponse callback;

+ (NSDictionary*)finalPayloadForPayload:(NSDictionary*)payload;

+ (id)requestForService:(TeakRequestServiceType)serviceType atEndpoint:(NSString*)endpoint usingMethod:(NSString*)method withPayload:(NSDictionary*)payload callback:(TeakRequestResponse)callback;
- (id)initForService:(TeakRequestServiceType)serviceType atEndpoint:(NSString*)endpoint usingMethod:(NSString*)method payload:(NSDictionary*)payload callback:(TeakRequestResponse)callback;

- (NSString*)description;

@end
