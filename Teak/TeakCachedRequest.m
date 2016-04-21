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

#import "Teak+Internal.h"
#import "TeakCachedRequest.h"
#import "TeakRequestThread.h"

@interface TeakCachedRequest ()

@property (strong, nonatomic, readwrite) NSString* requestId;
@property (strong, nonatomic, readwrite) NSDate* dateIssued;
@property (nonatomic, readwrite) NSUInteger retryCount;
@property (nonatomic, readwrite) sqlite3_uint64 cacheId;

@end

@implementation TeakCachedRequest

+ (id)requestForService:(TeakRequestServiceType)serviceType atEndpoint:(NSString*)endpoint withPayload:(NSDictionary*)payload inCache:(TeakCache*)cache
{
   NSUInteger retryCount = 0;
   TeakCachedRequest* ret = nil;
   NSDate* dateIssued = [NSDate date];

   CFUUIDRef theUUID = CFUUIDCreate(NULL);
   CFStringRef uuidString = CFUUIDCreateString(NULL, theUUID);
   CFRelease(theUUID);
   NSString* requestId = (__bridge NSString*)uuidString;

   ret = [[TeakCachedRequest alloc] initForService:serviceType
                                        atEndpoint:endpoint
                                           payload:payload
                                         requestId:requestId
                                        dateIssued:dateIssued
                                           cacheId:0
                                        retryCount:retryCount];
   ret.cacheId = [cache cacheRequest:ret];

   // Clean up
   CFRelease(uuidString);

   return ret;
}

- (id)initForService:(TeakRequestServiceType)serviceType atEndpoint:(NSString*)endpoint payload:(NSDictionary*)payload requestId:(NSString*)requestId dateIssued:(NSDate*)dateIssued cacheId:(sqlite3_uint64)cacheId retryCount:(NSUInteger)retryCount
{
   NSMutableDictionary* finalPayload = [payload mutableCopy];
   [finalPayload setObject:requestId forKey:@"request_id"];
   [finalPayload setObject:[NSNumber numberWithLongLong:(uint64_t)[dateIssued timeIntervalSince1970]] forKey:@"request_date"];

   self = [super initForService:serviceType atEndpoint:endpoint usingMethod:TeakRequestTypePOST payload:finalPayload callback:^(TeakRequest* request, NSHTTPURLResponse* response, NSData* data, TeakRequestThread* requestThread) {
      TeakCachedRequest* cachedRequest = (TeakCachedRequest*)request;
      [cachedRequest requestCallbackStatus:response data:data thread:requestThread];
   }];

   if(self)
   {
      self.requestId = requestId;
      self.dateIssued = dateIssued;
      self.retryCount = retryCount;
      self.cacheId = cacheId;
   }
   return self;
}

- (NSString*)description
{
   return [NSString stringWithFormat:@"Teak Request: {\n\t'request_servicetype':'%d'\n\t'request_endpoint':'%@',\n\t'request_payload':'%@',\n\t'request_id':'%@',\n\t'request_date':'%@',\n\t'retry_count':'%lu'\n}", self.serviceType, self.endpoint, self.payload, self.requestId, self.dateIssued, (unsigned long)self.retryCount];
}

- (void)requestCallbackStatus:(NSHTTPURLResponse*)response data:(NSData*)data thread:(TeakRequestThread*)requestThread
{
   //NSError* error = nil;
   //NSDictionary* jsonReply = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

   if(response.statusCode < 500)
   {
      [requestThread.cache removeRequestFromCache:self];
   }
   else
   {
      [requestThread.cache addRetryInCacheForRequest:self];
   }
}

@end
