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

#import "TeakAppConfiguration.h"
#import "TeakDeviceConfiguration.h"
#import "TeakSession.h"

#include <CommonCrypto/CommonHMAC.h>

///// TeakRequest

@interface TeakRequest ()
@property (strong, nonatomic, readwrite) NSString* endpoint;
@property (strong, nonatomic, readwrite) NSDictionary* payload;
@property (copy, nonatomic, readwrite) TeakRequestResponse callback;
@property (strong, nonatomic) NSString* hostname;
@property (strong, nonatomic) NSString* requestId;
@property (strong, nonatomic) TeakSession* session;
@property (strong, nonatomic) NSDate* sendDate;

- (TeakRequest*)initWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(nullable TeakRequestResponse)callback addCommonPayload:(BOOL)addCommonToPayload;
@end

///// TeakBatchedRequest

@interface TeakBatchedRequest : TeakRequest
@property (strong, nonatomic) dispatch_block_t scheduledBlock;
@property (strong, nonatomic) NSMutableArray* callbacks;
@property (strong, nonatomic) NSMutableArray* batch;
@property (nonatomic) long delayTimeInSeconds;

- (void)send;
- (BOOL)addPayload:(nonnull NSDictionary*)payload forEndpoint:(nonnull NSString*)endpoint withCallback:(nullable TeakRequestResponse)callback;
@end

///// TeakTrackEventBatchedRequest

@interface TeakTrackEventBatchedRequest : TeakBatchedRequest
+ (TeakTrackEventBatchedRequest*)currentBatchForSession:(TeakSession*)session;
@end

///// TeakRequestURLDelegate

@interface TeakRequestURLDelegate : NSObject <NSURLSessionTaskDelegate, NSURLSessionDataDelegate>
@property (strong, nonatomic) NSMutableDictionary* responseData;
@end

///// TeakRequest impl

@implementation TeakRequest

+ (NSURLSession*)sharedURLSession {
  static NSURLSession* session = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSURLSessionConfiguration* sessionConfiguration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    sessionConfiguration.URLCache = nil;
    sessionConfiguration.URLCredentialStorage = nil;
    sessionConfiguration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    sessionConfiguration.HTTPAdditionalHeaders = @{@"X-Teak-DeviceType" : @"API"};
    session = [NSURLSession sessionWithConfiguration:sessionConfiguration
                                            delegate:[[TeakRequestURLDelegate alloc] init]
                                       delegateQueue:nil];
  });
  return session;
}

+ (NSMutableDictionary*)requestsInFlight {
  static NSMutableDictionary* dict = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    dict = [[NSMutableDictionary alloc] init];
  });
  return dict;
}

+ (nullable TeakRequest*)requestWithSession:(nonnull TeakSession*)session forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(nullable TeakRequestResponse)callback {
  return [TeakRequest requestWithSession:session forHostname:@"gocarrot.com" withEndpoint:endpoint withPayload:payload callback:callback];
}

+ (nullable TeakRequest*)requestWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(nullable TeakRequestResponse)callback {
  TeakRequest* ret = nil;
  if ([@"/me/events" isEqualToString:endpoint]) {

  } else {
    ret = [[TeakRequest alloc] initWithSession:session forHostname:hostname withEndpoint:endpoint withPayload:payload callback:callback addCommonPayload:YES];
  }
  return ret;
}

- (TeakRequest*)initWithSession:(nonnull TeakSession*)session forHostname:(nonnull NSString*)hostname withEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload callback:(nullable TeakRequestResponse)callback addCommonPayload:(BOOL)addCommonToPayload {
  self = [super init];
  if (self) {
    CFUUIDRef theUUID = CFUUIDCreate(NULL);
    CFStringRef string = CFUUIDCreateString(NULL, theUUID);
    CFRelease(theUUID);
    self.requestId = [(__bridge NSString*)string stringByReplacingOccurrencesOfString:@"-" withString:@""];
    CFRelease(string);
    self.endpoint = endpoint;
    self.callback = callback;
    self.hostname = hostname;
    self.session = session;

    @try {
      NSMutableDictionary* payloadWithCommon = [NSMutableDictionary dictionaryWithDictionary:payload];
      if (addCommonToPayload) {
        [payloadWithCommon addEntriesFromDictionary:@{
          @"appstore_name" : @"apple",
          @"game_id" : self.session.appConfiguration.appId,
          @"sdk_version" : [Teak sharedInstance].sdkVersion,
          @"sdk_platform" : self.session.deviceConfiguration.platformString,
          @"app_version" : self.session.appConfiguration.appVersion,
          @"device_model" : self.session.deviceConfiguration.deviceModel,
          @"bundle_id" : self.session.appConfiguration.bundleId,
          @"device_id" : self.session.deviceConfiguration.deviceId,
          @"is_sandbox" : [NSNumber numberWithBool:!self.session.appConfiguration.isProduction]
        }];
        if (self.session.userId) {
          payloadWithCommon[@"api_key"] = self.session.userId;
        }
      }
      self.payload = payloadWithCommon;
    } @catch (NSException* exception) {
      TeakLog_e(@"request.error.payload", @{@"error" : exception.reason});
      return nil;
    }
  }
  return self;
}

- (nonnull NSDictionary*)signedPayload:(nonnull NSDictionary*)payloadToSign withSession:(nonnull TeakSession*)session {
  teak_try {
    NSString* path = self.endpoint;
    if (path == nil || path.length < 1) path = @"/";

    // Build query string to sign
    NSArray* queryKeysSorted = [[payloadToSign allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSMutableString* sortedQueryString = [[NSMutableString alloc] init];
    for (int i = 0; i < queryKeysSorted.count; i++) {
      NSString* key = queryKeysSorted[i];
      id value = [payloadToSign objectForKey:key];

      NSString* valueString = value;
      if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        NSError* error = nil;
        NSData* jsonData = [NSJSONSerialization dataWithJSONObject:value options:0 error:&error];
        if (error) {
          TeakLog_e(@"request.error.json", @{@"value" : value, @"error" : error});
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
      NSString* key = queryKeysSorted[i];
      id value = payloadToSign[key];
      NSString* valueString = value;
      if ([value isKindOfClass:[NSDictionary class]] || [value isKindOfClass:[NSArray class]]) {
        NSError* error = nil;
        NSData* jsonData = [NSJSONSerialization dataWithJSONObject:value options:0 error:&error];

        if (error) {
          TeakLog_e(@"request.error.json", @{@"value" : value, @"error" : error});
          valueString = [value description];
        } else {
          valueString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        }
      }
      retParams[key] = valueString;
    }
    retParams[@"sig"] = sigString;

    return retParams;
  }
  teak_catch_report;

  return payloadToSign;
}

- (void)send {
  teak_try {
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://%@%@", self.hostname, self.endpoint]]];
    NSDictionary* signedPayload = [self signedPayload:self.payload withSession:self.session];
    NSString* boundry = @"-===-httpB0unDarY-==-";

    NSMutableData* postData = [[NSMutableData alloc] init];

    for (NSString* key in signedPayload) {
      [postData appendData:[[NSString stringWithFormat:@"--%@\r\n", boundry] dataUsingEncoding:NSUTF8StringEncoding]];
      [postData appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", key, [signedPayload objectForKey:key]] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [postData appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundry] dataUsingEncoding:NSUTF8StringEncoding]];

    [request setHTTPMethod:@"POST"];
    [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[postData length]] forHTTPHeaderField:@"Content-Length"];
    [request setHTTPBody:postData];
    NSString* charset = (NSString*)CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding));
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; charset=%@; boundary=%@", charset, boundry] forHTTPHeaderField:@"Content-Type"];

    NSURLSessionDataTask* dataTask = [[TeakRequest sharedURLSession] dataTaskWithRequest:request];
    [TeakRequest requestsInFlight][@(dataTask.taskIdentifier)] = self;
    self.sendDate = [NSDate date];
    [dataTask resume];

    TeakLog_i(@"request.send", [self to_h]);
  }
  teak_catch_report;
}

- (NSDictionary*)to_h {
  return @{
    @"request_id" : self.requestId,
    @"hostname" : self.hostname == nil ? [NSNull null] : self.hostname,
    @"endpoint" : self.endpoint,
    @"payload" : self.payload,
    @"session" : self.session.sessionId
  };
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<%@: %p> endpoint: %@; callback: %p; payload: %@",
                                    NSStringFromClass([self class]),
                                    self,
                                    self.endpoint,
                                    self.callback,
                                    self.payload];
}

- (void)response:(NSURLResponse*)response payload:(NSDictionary*)payload withError:(NSError*)error {
  TeakUnused(error);

  teak_try {
    NSMutableDictionary* h = [NSMutableDictionary dictionaryWithDictionary:[self to_h]];

    [h setValue:[NSNumber numberWithDouble:[self.sendDate timeIntervalSinceNow] * -1000.0] forKey:@"response_time"];
    [h setValue:payload forKey:@"payload"];
    TeakLog_i(@"request.reply", h);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      teak_try {
        if (self.callback) {
          self.callback(response, payload);
        }
      }
      teak_catch_report;
    });
  }
  teak_catch_report;
}

@end

///// TeakTrackEventBatchedRequest impl

@implementation TeakTrackEventBatchedRequest

+ (TeakTrackEventBatchedRequest*)currentBatchForSession:(TeakSession*)session {
  static TeakTrackEventBatchedRequest* currentBatch = nil;
  if (currentBatch == nil) {
    //currentBatch =
  }
  return currentBatch;
}

@end

///// TeakBatchedRequest impl

@implementation TeakBatchedRequest

- (id)init {
  self = [super init];
  if (self) {
    self.callbacks = [[NSMutableArray alloc] init];
    self.batch = [[NSMutableArray alloc] init];
    self.delayTimeInSeconds = 5; // HAX
  }
  return self;
}

- (BOOL)addPayload:(nonnull NSDictionary*)payload forEndpoint:(nonnull NSString*)endpoint withCallback:(nullable TeakRequestResponse)callback {
  if (payload == nil || endpoint == nil) return NO;

  if (self.scheduledBlock != nil) {
    dispatch_block_cancel(self.scheduledBlock);
    if (dispatch_block_testcancel(self.scheduledBlock) == 0) {
      // TODO: This needs to be tested in-depth, maybe dispatch_block_notifiy should be used
      return NO;
    }
  }

  if (callback != nil) {
    [self.callbacks addObject:[callback copy]];
  }

  [self.batch addObject:payload];
  self.scheduledBlock = dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, ^{
    [self prepareAndSend];
  });

  dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, self.delayTimeInSeconds * NSEC_PER_SEC);
  dispatch_after(delayTime, dispatch_get_main_queue(), self.scheduledBlock);
  return YES;
}

- (void)send {
  // No-op
}

- (void)prepareAndSend {
  [super send];
}

@end

///// TeakRequestURLDelegate impl

@implementation TeakRequestURLDelegate

- (id)init {
  self = [super init];
  if (self) {
    self.responseData = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)dataTask didReceiveResponse:(NSURLResponse*)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
  completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession*)session dataTask:(NSURLSessionDataTask*)dataTask didReceiveData:(NSData*)data {
  teak_try {
    NSMutableData* responseData = self.responseData[@(dataTask.taskIdentifier)];
    if (!responseData) {
      self.responseData[@(dataTask.taskIdentifier)] = [NSMutableData dataWithData:data];
    } else {
      [responseData appendData:data];
    }
  }
  teak_catch_report;
}

- (void)URLSession:(NSURLSession*)session task:(NSURLSessionTask*)dataTask didCompleteWithError:(NSError*)error {
  NSDictionary* reply = @{};
  if (error) {
    // TODO: Handle error
  } else {
    teak_try {
      reply = (NSDictionary*)[NSJSONSerialization JSONObjectWithData:self.responseData[@(dataTask.taskIdentifier)]
                                                             options:kNilOptions
                                                               error:&error];
      if (error) {
        reply = @{};
      }
    }
    teak_catch_report;
  }
  [self.responseData removeObjectForKey:@(dataTask.taskIdentifier)];
  TeakRequest* request = [TeakRequest requestsInFlight][@(dataTask.taskIdentifier)];
  if (request) {
    [request response:dataTask.response payload:reply withError:error];
    [[TeakRequest requestsInFlight] removeObjectForKey:@(dataTask.taskIdentifier)];
  }
}

@end
