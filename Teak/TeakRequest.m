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

#import "TeakRequest.h"
#import "Teak+Internal.h"

NSString* const TeakRequestTypePOST = @"POST";

@interface TeakRequest ()

@property (nonatomic, readwrite) TeakRequestServiceType serviceType;
@property (strong, nonatomic, readwrite) NSString* endpoint;
@property (strong, nonatomic, readwrite) NSDictionary* payload;
@property (strong, nonatomic, readwrite) NSString* method;
@property (strong, nonatomic, readwrite) TeakRequestResponse callback;

@end

@implementation TeakRequest

+ (id)requestForService:(TeakRequestServiceType)serviceType atEndpoint:(NSString*)endpoint usingMethod:(NSString*)method withPayload:(NSDictionary*)payload callback:(TeakRequestResponse)callback
{
   return [[TeakRequest alloc] initForService:serviceType
                                     atEndpoint:endpoint
                                    usingMethod:method
                                        payload:payload
                                       callback:callback];
}

+ (NSDictionary*)finalPayloadForPayload:(NSDictionary*)payload
{
   static NSDictionary* commonPayload;
   static dispatch_once_t onceToken;

   dispatch_once(&onceToken, ^{
      commonPayload = @{
                        @"api_key" : [Teak sharedInstance].userId,
                        @"game_id" : [Teak sharedInstance].appId,
                        @"sdk_version" : [Teak sharedInstance].sdkVersion,
                        @"sdk_platform" : [Teak sharedInstance].sdkPlatform,
                        @"app_version" : [Teak sharedInstance].appVersion
                        };
   });

   NSMutableDictionary* finalPayload = [NSMutableDictionary dictionaryWithDictionary:commonPayload];
   [finalPayload addEntriesFromDictionary:payload];

   return finalPayload;
}

- (id)initForService:(TeakRequestServiceType)serviceType atEndpoint:(NSString*)endpoint usingMethod:(NSString*)method payload:(NSDictionary*)payload callback:(TeakRequestResponse)callback
{
   self = [super init];
   if(self)
   {
      self.serviceType = serviceType;
      self.endpoint = endpoint;
      self.payload = [TeakRequest finalPayloadForPayload:payload];
      self.method = method;
      self.callback = callback;
   }
   return self;
}


- (NSString*)description
{
   return [NSString stringWithFormat:@"Teak Request: {\n\t'request_servicetype':'%d'\n\t'request_endpoint':'%@',\n\t'request_method':'%@',\n\t'request_payload':'%@'\n}", self.serviceType, self.endpoint, self.method, self.payload];
}

@end
