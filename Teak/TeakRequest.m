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
@property (copy, nonatomic, readwrite) TeakRequestResponse callback;
@property (strong, nonatomic) NSString* hostname;
@property (strong, nonatomic) NSURLSession* urlSession;
@property (strong, nonatomic) NSMutableData* receivedData;
@end

@implementation TeakRequest

- (TeakRequest*)initWithSession:(nonnull TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(TeakRequestResponse)callback {
   return [self initWithSession:session forHostname:@"gocarrot.com" withEndpoint:endpoint withPayload:payload callback:callback];
}

- (TeakRequest*)initWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(TeakRequestResponse)callback {
   self = [super init];
   if (self) {
      self.endpoint = endpoint;
      self.callback = callback;
      self.hostname = hostname;
      self.urlSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]
                                                      delegate:self
                                                 delegateQueue:nil];
      self.receivedData = [[NSMutableData alloc] init];
      [self.receivedData setLength:0];

      @try {
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
         if (session.userId) {
            [payloadWithCommon setObject:session.userId forKey:@"api_key"];
         }
         self.payload = [self signedPayload:payloadWithCommon withSession:session];
      } @catch (NSException* exception) {
         TeakLog(@"Error creating request payload. %@", exception);
         return nil;
      }
   }
   return self;
}

- (nonnull NSDictionary*)signedPayload:(nonnull NSDictionary*)payloadToSign withSession:(nonnull TeakSession*)session {
   @try {
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
   } @catch (NSException* exception) {
      TeakLog(@"Error while signing parameters. %@", exception);
      return payloadToSign;
   }
}

- (void)send {
   @try {
      NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://%@%@", self.hostname, self.endpoint]]];

      NSString* boundry = @"-===-httpB0unDarY-==-";
      
      NSMutableData* postData = [[NSMutableData alloc] init];
      
      for (NSString* key in self.payload) {
         [postData appendData:[[NSString stringWithFormat:@"--%@\r\n", boundry] dataUsingEncoding:NSUTF8StringEncoding]];
         [postData appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", key,[self.payload objectForKey:key]] dataUsingEncoding:NSUTF8StringEncoding]];
      }
      [postData appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundry] dataUsingEncoding:NSUTF8StringEncoding]];

      [request setHTTPMethod:@"POST"];
      [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[postData length]] forHTTPHeaderField:@"Content-Length"];
      [request setHTTPBody:postData];
      NSString* charset = (NSString*)CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding));
      [request setValue:[NSString stringWithFormat:@"multipart/form-data; charset=%@; boundary=%@", charset, boundry] forHTTPHeaderField:@"Content-Type"];

      NSURLSessionDataTask *dataTask = [self.urlSession dataTaskWithRequest:request];
      [dataTask resume];

      if ([Teak sharedInstance].enableDebugOutput) {
         TeakLog(@"Submitting request to '%@': %@", self.endpoint, self.payload);
      }
   } @catch(NSException* exception) {
      TeakLog(@"Error sending request. %@", exception);
   }
}

- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)dataTask didReceiveResponse:(NSURLResponse*)response completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler {
   // TODO: Check response
   completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)dataTask didReceiveData:(NSData*)data {
   @try {
      [self.receivedData appendData:data];
   } @catch(NSException* exception) {
      TeakLog(@"Error appending data from URLSession. %@", exception);
   }
}

- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)task didCompleteWithError:(NSError*)error {
   if (error) {
      // TODO: Handle error
   }
   else {
      @try {
         NSDictionary* reply = (NSDictionary*)[NSJSONSerialization JSONObjectWithData:self.receivedData options:kNilOptions error:&error];

         if ([Teak sharedInstance].enableDebugOutput) {
            TeakLog(@"Reply from '%@': %@", self.endpoint, reply);
         }

         dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            self.callback(task.response, reply);
         });
      } @catch(NSException* exception) {
         TeakLog(@"Error deserializing JSON reply. %@", exception);
      }
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
