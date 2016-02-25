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

#import <Teak/Teak.h>
#import "Teak+Internal.h"
#import "TeakRequestThread.h"
#import "TeakCachedRequest.h"
#import "AmazonSDKUtil.h"

#include <CommonCrypto/CommonHMAC.h>

@interface TeakRequestThread ()

@property (strong, nonatomic) NSMutableArray* requestQueue;
@property (strong, nonatomic, readwrite) TeakCache* cache;
@property (assign, nonatomic) Teak* teak;
@property (nonatomic) BOOL keepThreadRunning;
@property (strong, nonatomic) NSCondition* requestQueuePause;
@property (strong, nonatomic) NSString* postHostname;
@property (strong, nonatomic) NSString* metricsHostname;
@property (strong, nonatomic) NSString* authHostname;

@end

@implementation TeakRequestThread

- (id)initWithTeak:(Teak*)teak
{
   self = [super init];
   if(self)
   {
      self.requestQueue = [[NSMutableArray alloc] init];
      self.teak = teak;
      self.maxRetryCount = 0; // Infinite retries by default
      self.requestQueuePause = [[NSCondition alloc] init];
      self.cache = teak.cache;
      _isRunning = NO;
   }
   return self;
}

- (void)dealloc
{
   [self stop];
   self.requestQueue = nil;
}

- (void)start
{
   if(!self.isRunning)
   {
      self.keepThreadRunning = YES;
      [NSThread detachNewThreadSelector:@selector(requestQueueProc:) toTarget:self withObject:nil];
   }
}

- (void)stop
{
   if(self.isRunning)
   {
      // Signal thread to start up if it is waiting
      [self.requestQueuePause lock];
      self.keepThreadRunning = NO;
      [self.requestQueuePause signal];
      [self.requestQueuePause unlock];
   }
}

- (void)signal
{
   if(self.isRunning)
   {
      [self.requestQueuePause lock];
      [self.requestQueuePause signal];
      [self.requestQueuePause unlock];
   }
}

- (NSString*)hostForServiceType:(TeakRequestServiceType)serviceType
{
   switch(serviceType)
   {
      case TeakRequestServiceAuth:    return self.authHostname;
      case TeakRequestServiceMetrics: return self.metricsHostname;
      case TeakRequestServicePost:    return self.postHostname;
   }
}

- (BOOL)addRequestForService:(TeakRequestServiceType)serviceType atEndpoint:(NSString*)endpoint usingMethod:(NSString*)method withPayload:(NSDictionary*)payload
{
   return [self addRequestForService:serviceType atEndpoint:endpoint usingMethod:method withPayload:payload callback:nil atFront:NO];
}

- (BOOL)addRequestForService:(TeakRequestServiceType)serviceType atEndpoint:(NSString*)endpoint  usingMethod:(NSString*)method withPayload:(NSDictionary*)payload callback:(TeakRequestResponse)callback
{
   return [self addRequestForService:serviceType atEndpoint:endpoint usingMethod:method withPayload:payload callback:callback atFront:NO];
}

- (BOOL)addRequestForService:(TeakRequestServiceType)serviceType atEndpoint:(NSString*)endpoint  usingMethod:(NSString*)method withPayload:(NSDictionary*)payload callback:(TeakRequestResponse)callback atFront:(BOOL)atFront
{
   BOOL ret = YES;
   if(method == TeakRequestTypeGET)
   {

      TeakRequest* request = [TeakRequest requestForService:serviceType
                                                 atEndpoint:endpoint
                                                usingMethod:method
                                                withPayload:payload
                                                   callback:callback];
      if(request)
      {
         [self addRequestInQueue:request atFront:atFront];
      }
   }
   else
   {
      TeakCachedRequest* cachedRequest =
      [TeakCachedRequest requestForService:serviceType
                                atEndpoint:endpoint
                               withPayload:payload
                                   inCache:self.cache];

      if(cachedRequest)
      {
         [self addRequestInQueue:cachedRequest atFront:atFront];
      }

      ret = (cachedRequest != nil);
   }

   return ret;
}

- (void)addRequestInQueue:(TeakRequest*)request atFront:(BOOL)atFront
{
   if(request != nil)
   {
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
         @synchronized(self.requestQueue)
         {
            if(atFront)
            {
               [self.requestQueue insertObject:request atIndex:0];
            }
            else
            {
               [self.requestQueue addObject:request];
            }
         }
         [self signal];
      });
   }
}

- (void)loadQueueFromCache
{
   @synchronized(self.requestQueue)
   {
      [self.cache addRequestsIntoArray:self.requestQueue];
   }
}

- (NSMutableDictionary*)signedPostPayload:(TeakRequest*)request forHost:(NSString*)host
{
   NSString* path = request.endpoint;
   if(path == nil || path.length < 1) path = @"/";

   NSMutableDictionary* queryParamDict = [NSMutableDictionary dictionaryWithDictionary:request.payload];

   if(request.method != TeakRequestTypePOST)
   {
      [queryParamDict addEntriesFromDictionary:@{@"_method" : request.method}];
   }

   // Build query string to sign
   NSArray* queryKeysSorted = [[queryParamDict allKeys]
                               sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
   NSMutableString* sortedQueryString = [[NSMutableString alloc] init];
   for(int i = 0; i < queryKeysSorted.count; i++)
   {
      NSString* key = [queryKeysSorted objectAtIndex:i];

      // Skip signing "image_bytes" if it exists
      if([key compare:@"image_bytes"] == NSOrderedSame) continue;

      id value = [queryParamDict objectForKey:key];
      NSString* valueString = value;
      if([value isKindOfClass:[NSDictionary class]] ||
         [value isKindOfClass:[NSArray class]])
      {
         NSError* error = nil;

         NSData* jsonData = [NSJSONSerialization dataWithJSONObject:value options:0 error:&error];
         if(error)
         {
            NSLog(@"Error converting %@ to JSON: %@", value, error);
            valueString = [value description];
         }
         else
         {
            valueString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
         }
      }
      [sortedQueryString appendFormat:@"%@=%@%s", key, valueString,
       (i + 1 < queryKeysSorted.count ? "&" : "")];
   }

   NSString* stringToSign = [NSString stringWithFormat:@"%@\n%@\n%@\n%@", @"POST", host, path,
                             sortedQueryString];

   NSData* dataToSign = [stringToSign dataUsingEncoding:NSUTF8StringEncoding];
   uint8_t digestBytes[CC_SHA256_DIGEST_LENGTH];
   CCHmac(kCCHmacAlgSHA256, [self.teak.appSecret UTF8String], self.teak.appSecret.length,
          [dataToSign bytes], [dataToSign length], &digestBytes);

   NSData* digestData = [NSData dataWithBytes:digestBytes length:CC_SHA256_DIGEST_LENGTH];
   NSString* sigString = [NSDataWithBase64 base64EncodedStringFromData:digestData];

   // Build params dictionary with JSON object representations
   NSMutableDictionary* retParams = [[NSMutableDictionary alloc] init];
   for(int i = 0; i < queryKeysSorted.count; i++)
   {
      NSString* key = [queryKeysSorted objectAtIndex:i];
      id value = [queryParamDict objectForKey:key];
      NSString* valueString = value;
      if([value isKindOfClass:[NSDictionary class]] ||
         [value isKindOfClass:[NSArray class]])
      {
         NSError* error = nil;

         NSData* jsonData = [NSJSONSerialization dataWithJSONObject:value options:0 error:&error];
         if(error)
         {
            NSLog(@"Error converting %@ to JSON: %@", value, error);
            valueString = [value description];
         }
         else
         {
            valueString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
         }
      }
      [retParams setObject:valueString forKey:key];
   }
   [retParams setObject:sigString forKey:@"sig"];

   return retParams;
}

- (void)requestQueueProc:(id)context
{
   _isRunning = YES;

   while(self.keepThreadRunning)
   {
      @autoreleasepool
      {
         TeakCachedRequest* request = nil;

         @synchronized(self.requestQueue)
         {
            if(self.requestQueue.count > 0)
            {
               request = [self.requestQueue objectAtIndex:0];
               [self.requestQueue removeObjectAtIndex:0];
            }
         }

         if(request)
         {
            [self processRequest:request];
         }
         else
         {
            [self.requestQueuePause lock];

            // Populate cache
            [self loadQueueFromCache];

            // If queue is still empty, wait until it's not empty.
            while(self.requestQueue.count < 1 && self.keepThreadRunning) {
               [self.requestQueuePause wait];
            }
            [self.requestQueuePause unlock];
         }

         // 'jitter' request rate
         double val = (arc4random_uniform(100) / 100.0) - 0.5;
         [NSThread sleepForTimeInterval:1.0 + val];
      }
   }
   _isRunning = NO;
}

- (void)processRequest:(TeakRequest*)request
{
   NSString* host = [self hostForServiceType:request.serviceType];

   // If host is nil or empty, the server said "don't send me these now"
   if(!(host && host.length)) return;

   NSMutableDictionary* payload = [self signedPostPayload:request forHost:host];
   NSString* boundry = @"-===-httpB0unDarY-==-";

   NSMutableData* postData = [[NSMutableData alloc] init];

   for(NSString* key in payload)
   {
      // Skip image bytes here.
      if([key compare:@"image_bytes"] == NSOrderedSame) continue;

      [postData appendData:[[NSString stringWithFormat:@"--%@\r\n", boundry] dataUsingEncoding:NSUTF8StringEncoding]];
      [postData appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", key,[payload objectForKey:key]] dataUsingEncoding:NSUTF8StringEncoding]];
   }

   NSString* imageBytes = [payload objectForKey:@"image_bytes"];
   if(imageBytes)
   {
      // Attach image
      [payload removeObjectForKey:@"image_bytes"];
      [postData appendData:[[NSString stringWithFormat:@"--%@\r\n", boundry] dataUsingEncoding:NSUTF8StringEncoding]];
      [postData appendData:[@"Content-Disposition: form-data; name=\"image_bytes\"; filename=\"file.png\"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
      [postData appendData:[@"Content-Type: image/png\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
      [postData appendData:[NSDataWithBase64 dataWithBase64EncodedString:imageBytes]];
      [postData appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
   }
   [postData appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundry] dataUsingEncoding:NSUTF8StringEncoding]];

   NSMutableURLRequest* preppedRequest = nil;

   preppedRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@://%@%@", kDefaultHostUrlScheme, host, request.endpoint]]];

   [preppedRequest setHTTPBody:postData];
   [preppedRequest setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[postData length]]
         forHTTPHeaderField:@"Content-Length"];
   NSString* charset = (NSString*)CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding));
   [preppedRequest setValue:[NSString stringWithFormat:@"multipart/form-data; charset=%@; boundary=%@", charset, boundry]
         forHTTPHeaderField:@"Content-Type"];

   [preppedRequest setHTTPMethod:@"POST"];

   // Allocate response
   NSHTTPURLResponse* response = [[NSHTTPURLResponse alloc]
                                  initWithURL:preppedRequest.URL
                                  MIMEType:@"application/x-www-form-urlencoded"
                                  expectedContentLength:-1
                                  textEncodingName:nil];
   NSError* error = nil;

   // Issue request
   NSData* data = [NSURLConnection sendSynchronousRequest:preppedRequest
                                        returningResponse:&response
                                                    error:&error];

   // Handle response
   if(error && error.code != NSURLErrorUserCancelledAuthentication)
   {
      NSLog(@"Error submitting Teak request: %@", error);
   }
   else if(request.callback)
   {
      request.callback(request, response, data, self);
   }
}

@end
