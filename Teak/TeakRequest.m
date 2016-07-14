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
#import <Teak/Teak.h>

#import "TeakSession.h"
#import "TeakAppConfiguration.h"
#import "TeakDeviceConfiguration.h"

#include <CommonCrypto/CommonHMAC.h>

#define LOG_TAG "Teak:Request"

@interface TeakRequest ()
@property (strong, nonatomic, readwrite) NSString* endpoint;
@property (strong, nonatomic, readwrite) NSDictionary* payload;
@property (strong, nonatomic, readwrite) TeakRequestResponse callback;
@property (strong, nonatomic) NSString* hostname;
@property (strong, nonatomic) NSURLSession* urlSession;
@property (strong, nonatomic) NSMutableData* receivedData;
@end

@implementation TeakRequest

- (TeakRequest*)initWithSession:(nonnull TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(TeakRequestResponse)callback {
   self = [super init];
   if (self) {
      self.endpoint = endpoint;
      self.callback = [callback copy];
      self.hostname = @"gocarrot.com"; // HAX, TODO: Support other hostnames via RemoteConfiguration
      self.urlSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]
                                                      delegate:self
                                                 delegateQueue:nil];
      self.receivedData = [[NSMutableData alloc] init];
      [self.receivedData setLength:0];

      NSMutableDictionary* payloadWithCommon = [NSMutableDictionary dictionaryWithDictionary:payload];
      [payloadWithCommon addEntriesFromDictionary:@{
         @"appstore_name" : @"apple",
         @"game_id" : session.appConfiguration.appId,
         @"sdk_version" : [Teak sharedInstance].sdkVersion,
         @"sdk_platform" : session.deviceConfiguration.platformString,
         @"app_version" : session.appConfiguration.appVersion,
         @"device_model" : session.deviceConfiguration.deviceModel,
         @"bundle_id" : session.appConfiguration.bundleId,
         @"device_id" : session.deviceConfiguration.deviceId,
         @"is_sandbox" : [NSNumber numberWithBool:!session.appConfiguration.isProduction]
      }];
      self.payload = [self signedPayload:payloadWithCommon withSession:session];
   }
   return self;
}


- (nonnull NSDictionary*)signedPayload:(nonnull NSDictionary*)payloadToSign withSession:(nonnull TeakSession*)session {
   NSString* path = self.endpoint;
   if(path == nil || path.length < 1) path = @"/";

   // Build query string to sign
   NSArray* queryKeysSorted = [[payloadToSign allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
   NSMutableString* sortedQueryString = [[NSMutableString alloc] init];
   for (int i = 0; i < queryKeysSorted.count; i++) {
      NSString* key = [queryKeysSorted objectAtIndex:i];
      id value = [payloadToSign objectForKey:key];

      NSString* valueString = value;
      if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
         NSError* error = nil;
         NSData* jsonData = [NSJSONSerialization dataWithJSONObject:value options:0 error:&error];
         if (error) {
            TeakLog(@"Error converting %@ to JSON: %@", value, error);
            valueString = [value description];
         } else {
            valueString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
         }
      }
      [sortedQueryString appendFormat:@"%@=%@%s", key, valueString, (i + 1 < queryKeysSorted.count ? "&" : "")];
   }

   NSString* stringToSign = [NSString stringWithFormat:@"%@\n%@\n%@\n%@", @"POST", self.hostname, path, sortedQueryString];

   NSData* dataToSign = [stringToSign dataUsingEncoding:NSUTF8StringEncoding];
   uint8_t digestBytes[CC_SHA256_DIGEST_LENGTH];
   CCHmac(kCCHmacAlgSHA256, [session.appConfiguration.apiKey UTF8String], session.appConfiguration.apiKey.length, [dataToSign bytes], [dataToSign length], &digestBytes);

   NSData* digestData = [NSData dataWithBytes:digestBytes length:CC_SHA256_DIGEST_LENGTH];
   NSString* sigString = [digestData base64EncodedStringWithOptions:0];

   // Build params dictionary with JSON object representations
   NSMutableDictionary* retParams = [[NSMutableDictionary alloc] init];
   for (int i = 0; i < queryKeysSorted.count; i++) {
      NSString* key = [queryKeysSorted objectAtIndex:i];
      id value = [payloadToSign objectForKey:key];
      NSString* valueString = value;
      if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
         NSError* error = nil;
         NSData* jsonData = [NSJSONSerialization dataWithJSONObject:value options:0 error:&error];

         if (error) {
            TeakLog(@"Error converting %@ to JSON: %@", value, error);
            valueString = [value description];
         } else {
            valueString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
         }
      }
      [retParams setObject:valueString forKey:key];
   }
   [retParams setObject:sigString forKey:@"sig"];

   return retParams;
}

- (void)send {
   NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://%@%@", self.hostname, self.endpoint]]];
   NSData* payloadData = [NSJSONSerialization dataWithJSONObject:self.payload options:0 error:nil];

   [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
   [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
   //[request setValue:@"gzip" forHTTPHeaderField:@"Content-Encoding"]; // TODO: gzip?
   [request setValue:@"teak" forHTTPHeaderField:@"User-Agent"];
   [request setHTTPMethod:@"POST"];
   [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[payloadData length]] forHTTPHeaderField:@"Content-Length"];
   [request setHTTPBody:payloadData];

   NSURLSessionDataTask *dataTask = [self.urlSession dataTaskWithRequest:request];
   [dataTask resume];
}

- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)dataTask didReceiveResponse:(NSURLResponse*)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
   // TODO: Check response
   completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)dataTask didReceiveData:(NSData*)data {
   [self.receivedData appendData:data];
}

- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(NSError*)error {
   if (error) {
      // TODO: Handle error
   }
   else {
      NSDictionary* reply = (NSDictionary*)[NSJSONSerialization JSONObjectWithData:self.receivedData options:kNilOptions error:&error];
      self.callback(task.response, reply);
   }
}

- (NSString*)description {
   return [NSString stringWithFormat:@"<%@: %p> endpoint: %@; callback: %p; payload: %@",
           NSStringFromClass([self class]),
           self,
           self.endpoint,
           self.callback,
           self.payload];
}

@end
