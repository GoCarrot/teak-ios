/* Teak -- Copyright (C) 2017 GoCarrot Inc.
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

#import "TeakNotificationService.h"

@interface TeakNotificationService ()
@property (strong, nonatomic) void (^contentHandler)(UNNotificationContent* contentToDeliver);
@property (strong, nonatomic) UNMutableNotificationContent* bestAttemptContent;
@property (strong, nonatomic) NSURLSession* session;

- (void)sendMetricForPayload:(NSDictionary*)payload;
@end

NSString* TeakNSStringOrNilFor(id object) {
  if (object == nil) return nil;

  NSString* ret = nil;
  @try {
    ret = ((object == nil || [object isKindOfClass:[NSString class]]) ? object : [object stringValue]);
  } @catch (NSException* ignored) {
  }
  return ret;
}

@implementation TeakNotificationService

- (void)didReceiveNotificationRequest:(UNNotificationRequest*)request withContentHandler:(void (^)(UNNotificationContent* _Nonnull))contentHandler {
  self.contentHandler = contentHandler;
  self.bestAttemptContent = [request.content mutableCopy];

  @try {
    NSDictionary* notification = request.content.userInfo[@"aps"];
    NSString* teakNotifId = TeakNSStringOrNilFor(notification[@"teakNotifId"]);
    if ([teakNotifId length] > 0) {
      // TODO: May want to use backgroundSession?
      self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];

      // HACK FOR TESTING
      self.bestAttemptContent.title = [NSString stringWithFormat:@"%@", teakNotifId];

      // Send notification_received metric
      NSString* teakUserId = TeakNSStringOrNilFor(notification[@"teakUserId"]);
      if ([teakUserId length] > 0) {
        NSDictionary* payload = @{
          @"user_id" : teakUserId,
          @"platform_id" : teakNotifId,
          @"network_id" : @3
        };
        [self sendMetricForPayload:payload];
      }
    }
  }
  @finally {
    self.contentHandler(self.bestAttemptContent);
  }
}

- (void)serviceExtensionTimeWillExpire {
  [self.session invalidateAndCancel];
  self.contentHandler(self.bestAttemptContent);
}

- (void)sendMetricForPayload:(NSDictionary*)payload {
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://parsnip.gocarrot.com/notification_received"]];

  NSString* boundry = @"-===-httpB0unDarY-==-";

  NSMutableData* postData = [[NSMutableData alloc] init];

  for (NSString* key in payload) {
    [postData appendData:[[NSString stringWithFormat:@"--%@\r\n", boundry] dataUsingEncoding:NSUTF8StringEncoding]];
    [postData appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", key, [payload objectForKey:key]] dataUsingEncoding:NSUTF8StringEncoding]];
  }
  [postData appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundry] dataUsingEncoding:NSUTF8StringEncoding]];

  [request setHTTPMethod:@"POST"];
  [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[postData length]] forHTTPHeaderField:@"Content-Length"];
  [request setHTTPBody:postData];
  NSString* charset = (NSString*)CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding));
  [request setValue:[NSString stringWithFormat:@"multipart/form-data; charset=%@; boundary=%@", charset, boundry] forHTTPHeaderField:@"Content-Type"];

  NSURLSessionUploadTask* uploadTask =
      [self.session uploadTaskWithRequest:request
                                 fromData:nil
                        completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                          [self.session finishTasksAndInvalidate];
                        }];
  [uploadTask resume];
}

@end
