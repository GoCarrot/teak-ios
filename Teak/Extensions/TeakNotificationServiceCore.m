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

#import <MobileCoreServices/MobileCoreServices.h>
#import <Teak/TeakNotificationServiceCore.h>

@interface TeakNotificationServiceCore ()
@property (strong, nonatomic) void (^contentHandler)(UNNotificationContent*);
@property (strong, nonatomic) UNMutableNotificationContent* bestAttemptContent;
@property (strong, nonatomic) NSURLSession* session;
@property (strong, nonatomic) NSOperationQueue* operationQueue;
@property (strong, nonatomic) NSOperation* contentHandlerOperation;
@property (strong, atomic) NSMutableArray* attachments;

- (NSOperation*)sendMetricForPayload:(NSDictionary*)payload;
- (NSOperation*)loadAttachment:(NSURL*)attachmentUrl forMIMEType:(NSString*)mimeType;
@end

@implementation TeakNotificationServiceCore

- (void)didReceiveNotificationRequest:(UNNotificationRequest*)request withContentHandler:(void (^)(UNNotificationContent* _Nonnull))contentHandler {
  self.contentHandler = contentHandler;
  self.bestAttemptContent = [request.content mutableCopy];
  self.attachments = [[NSMutableArray alloc] init];
  self.operationQueue = [[NSOperationQueue alloc] init];
  self.contentHandlerOperation = [NSBlockOperation blockOperationWithBlock:^{
    [self.session finishTasksAndInvalidate];
    self.contentHandler(self.bestAttemptContent);
  }];

  @try {
    NSDictionary* notification = request.content.userInfo[@"aps"];
    NSString* teakNotifId = TeakNSStringOrNilFor(notification[@"teakNotifId"]);
    if ([teakNotifId length] > 0) {
      self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];

      // Load attachments
      NSOperation* assignAttachmentsOperation = [NSBlockOperation blockOperationWithBlock:^{
        self.bestAttemptContent.attachments = self.attachments;
      }];
      [self.contentHandlerOperation addDependency:assignAttachmentsOperation];

      NSArray* attachments = notification[@"attachments"];
      for (NSDictionary* a in attachments) {
        NSURL* attachmentUrl = [NSURL URLWithString:a[@"url"]];
        if (attachmentUrl != nil) {
          NSOperation* attachmentOperation = [self loadAttachment:attachmentUrl forMIMEType:a[@"mime_type"]];
          [assignAttachmentsOperation addDependency:attachmentOperation];
        }
      }
      [self.operationQueue addOperation:assignAttachmentsOperation];

      // Send notification_received metric
      NSString* teakUserId = TeakNSStringOrNilFor(notification[@"teakUserId"]);
      if ([teakUserId length] > 0) {
        NSDictionary* payload = @{
          @"user_id" : teakUserId,
          @"platform_id" : teakNotifId,
          @"network_id" : @3
        };
        NSOperation* metricOperation = [self sendMetricForPayload:payload];
        [self.contentHandlerOperation addDependency:metricOperation];
      }
    }
  }
  @finally {
    [self.operationQueue addOperation:self.contentHandlerOperation];
  }
}

- (void)serviceExtensionTimeWillExpire {
  [self.session invalidateAndCancel];
  self.contentHandler(self.bestAttemptContent);
}

- (NSOperation*)loadAttachment:(NSURL*)attachmentUrl forMIMEType:(NSString*)mimeType {
  __block UNNotificationAttachment* attachment;
  NSOperation* attachmentOperation = [NSBlockOperation blockOperationWithBlock:^{
    if (attachment != nil) {
      [self.attachments addObject:attachment];
    }
  }];

  NSString* uti = CFBridgingRelease(UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (__bridge CFStringRef)mimeType, NULL));
  NSString* extension = (NSString*)CFBridgingRelease(UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)uti, kUTTagClassFilenameExtension));

  [[self.session downloadTaskWithURL:attachmentUrl
                   completionHandler:^(NSURL* temporaryFileLocation, NSURLResponse* response, NSError* error) {
                     if (error != nil) {
                       NSLog(@"%@", error.localizedDescription);
                     } else {
                       NSFileManager* fileManager = [NSFileManager defaultManager];
                       NSString* pathWithExtension = [NSString stringWithFormat:@"%@.%@", temporaryFileLocation.path, extension];
                       NSURL* localUrl = [NSURL fileURLWithPath:pathWithExtension];
                       [fileManager moveItemAtURL:temporaryFileLocation toURL:localUrl error:&error];

                       if (error == nil) {
                         attachment = [UNNotificationAttachment attachmentWithIdentifier:@"" URL:localUrl options:nil error:&error];
                         if (error != nil) {
                           NSLog(@"%@", error.localizedDescription);
                         }
                       } else {
                         NSLog(@"%@", error.localizedDescription);
                       }
                     }
                     [self.operationQueue addOperation:attachmentOperation];
                   }] resume];

  return attachmentOperation;
}

- (NSOperation*)sendMetricForPayload:(NSDictionary*)payload {
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://parsnip.gocarrot.com/notification_received"]];

  NSString* boundry = @"-===-httpB0unDarY-==-";

  NSMutableData* postData = [[NSMutableData alloc] init];

  for (NSString* key in payload) {
    [postData appendData:[[NSString stringWithFormat:@"--%@\r\n", boundry] dataUsingEncoding:NSUTF8StringEncoding]];
    [postData appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", key, payload[key]] dataUsingEncoding:NSUTF8StringEncoding]];
  }
  [postData appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundry] dataUsingEncoding:NSUTF8StringEncoding]];

  [request setHTTPMethod:@"POST"];
  [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[postData length]] forHTTPHeaderField:@"Content-Length"];
  [request setHTTPBody:postData];
  NSString* charset = (NSString*)CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding));
  [request setValue:[NSString stringWithFormat:@"multipart/form-data; charset=%@; boundary=%@", charset, boundry] forHTTPHeaderField:@"Content-Type"];

  NSOperation* metricOperation = [NSBlockOperation blockOperationWithBlock:^{}];

  NSURLSessionUploadTask* uploadTask =
      [self.session uploadTaskWithRequest:request
                                 fromData:nil
                        completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                          [self.operationQueue addOperation:metricOperation];
                        }];
  [uploadTask resume];
  return metricOperation;
}

@end
