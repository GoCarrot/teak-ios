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
#import <SystemConfiguration/SystemConfiguration.h>
#import <Teak/TeakNotificationServiceCore.h>
#import <UIKit/UIKit.h>

#import <sys/utsname.h>

@interface TeakNotificationServiceCore ()
@property (strong, nonatomic) void (^contentHandler)(UNNotificationContent*);
@property (strong, nonatomic) UNMutableNotificationContent* bestAttemptContent;
@property (strong, nonatomic) NSURLSession* session;
@property (strong, nonatomic) NSOperationQueue* operationQueue;
@property (strong, nonatomic) NSOperation* contentHandlerOperation;
@property (strong, atomic) NSMutableArray* attachments;

- (NSOperation*)sendMetricForPayload:(NSDictionary*)payload;
- (NSOperation*)loadAttachment:(NSURL*)attachmentUrl forMIMEType:(NSString*)mimeType atIndex:(int)index;
+ (NSString*)connectionTypeToHost:(NSString*)host;
@end

@implementation TeakNotificationServiceCore

- (void)didReceiveNotificationRequest:(UNNotificationRequest*)request withContentHandler:(void (^)(UNNotificationContent* _Nonnull))contentHandler {
  self.contentHandler = contentHandler;
  self.bestAttemptContent = [request.content mutableCopy];
  self.operationQueue = [[NSOperationQueue alloc] init];
  self.contentHandlerOperation = [NSBlockOperation blockOperationWithBlock:^{
    [self.session finishTasksAndInvalidate];
    self.contentHandler(self.bestAttemptContent);
  }];

  NSDictionary* notification = self.bestAttemptContent.userInfo[@"aps"];

  // Get device model, resolution, and if they are on wifi or celular
  NSMutableArray* additionalQueryItems = [[NSMutableArray alloc] init];

  // Width/height
  CGSize nativeScreenSize = [UIScreen mainScreen].nativeBounds.size;
  NSString* widthAsString = [NSString stringWithFormat:@"%.1f", nativeScreenSize.width];
  NSString* heightAsString = [NSString stringWithFormat:@"%.1f", nativeScreenSize.height];
  [additionalQueryItems addObject:[NSURLQueryItem queryItemWithName:@"width" value:widthAsString]];
  [additionalQueryItems addObject:[NSURLQueryItem queryItemWithName:@"height" value:heightAsString]];

  // Device model
  struct utsname systemInfo;
  uname(&systemInfo);
  NSString* deviceModel = @"unknown";
  @try {
    deviceModel = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
  } @finally {
    [additionalQueryItems addObject:[NSURLQueryItem queryItemWithName:@"device_model" value:deviceModel]];
  }

  // Wifi?
  NSString* connectionType = @"unknown";
  if (notification != nil && notification[@"content"] != nil) {
    @try {
      NSURLComponents* attachmentUrlComponents = [NSURLComponents componentsWithString:notification[@"content"][@"url"]];
      connectionType = [TeakNotificationServiceCore connectionTypeToHost:attachmentUrlComponents.host];
    } @finally {
      // Chomp exception is fine
    }
  }
  [additionalQueryItems addObject:[NSURLQueryItem queryItemWithName:@"connection_type" value:connectionType]];

  @try {
    NSString* teakNotifId = TeakNSStringOrNilFor(notification[@"teakNotifId"]);
    if ([teakNotifId length] > 0) {
      self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];

      // Process APS thumbnail, content and actions into an array of attachments
      // Replace URL in actions with index into array of attachments
      NSMutableArray* orderedAttachments = [[NSMutableArray alloc] init];
      if (notification[@"thumbnail"] != nil && notification[@"thumbnail"] != [NSNull null]) {
        [orderedAttachments addObject:notification[@"thumbnail"]];
      }

      NSNumber* contentIndex = [NSNumber numberWithUnsignedInteger:[orderedAttachments count]];

      if (notification[@"content"] != nil) {
        [orderedAttachments addObject:notification[@"content"]];
      }

      NSMutableDictionary* processedActions = [[NSMutableDictionary alloc] init];
      for (NSString* key in notification[@"playableActions"]) {
        // If the action is null, launch the app
        if (notification[@"playableActions"][key] == nil || notification[@"playableActions"][key] == [NSNull null]) {
          processedActions[key] = @-1;
        } else {
          processedActions[key] = [NSNumber numberWithInteger:[orderedAttachments count]];
          [orderedAttachments addObject:notification[@"playableActions"][key]];
        }
      }

      // Assign processed actions dictionary and content index
      {
        NSMutableDictionary* mutableUserInfo = [self.bestAttemptContent.userInfo mutableCopy];
        NSMutableDictionary* mutableAps = [mutableUserInfo[@"aps"] mutableCopy];
        mutableAps[@"content"] = contentIndex;
        mutableAps[@"playableActions"] = processedActions;
        mutableUserInfo[@"aps"] = mutableAps;
        self.bestAttemptContent.userInfo = mutableUserInfo;
        notification = mutableAps;
      }

      // Allocate attachments array with placeholders
      self.attachments = [[NSMutableArray alloc] initWithCapacity:[orderedAttachments count]];
      for (int i = 0; i < [orderedAttachments count]; i++) {
        [self.attachments addObject:[NSNull null]];
      }

      // Load attachments
      NSOperation* assignAttachmentsOperation = [NSBlockOperation blockOperationWithBlock:^{
        self.bestAttemptContent.attachments = self.attachments;
      }];
      [self.contentHandlerOperation addDependency:assignAttachmentsOperation];

      for (int i = 0; i < [orderedAttachments count]; i++) {
        NSDictionary* attachment = orderedAttachments[i];
        NSURLComponents* attachmentUrlComponents = [NSURLComponents componentsWithString:attachment[@"url"]];
        if (attachmentUrlComponents != nil) {
          // Add width, height, device_model, and wifi
          NSMutableArray* queryItems = [attachmentUrlComponents.queryItems mutableCopy];
          [queryItems addObjectsFromArray:additionalQueryItems];
          attachmentUrlComponents.queryItems = queryItems;

          NSOperation* attachmentOperation = [self loadAttachment:attachmentUrlComponents.URL forMIMEType:attachment[@"mime_type"] atIndex:i];
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
  } @finally {
    [self.operationQueue addOperation:self.contentHandlerOperation];
  }
}

- (void)serviceExtensionTimeWillExpire {
  [self.session invalidateAndCancel];
  self.contentHandler(self.bestAttemptContent);
}

- (NSOperation*)loadAttachment:(NSURL*)attachmentUrl forMIMEType:(NSString*)mimeType atIndex:(int)index {
  __block UNNotificationAttachment* attachment;
  NSOperation* attachmentOperation = [NSBlockOperation blockOperationWithBlock:^{
    if (attachment != nil) {
      self.attachments[index] = attachment;
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

+ (NSString*)connectionTypeToHost:(NSString*)host {
  SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, [host UTF8String]);
  SCNetworkReachabilityFlags flags;
  BOOL success = SCNetworkReachabilityGetFlags(reachability, &flags);
  CFRelease(reachability);
  if (!success) {
    return @"unknown";
  }
  BOOL isReachable = ((flags & kSCNetworkReachabilityFlagsReachable) != 0);
  BOOL needsConnection = ((flags & kSCNetworkReachabilityFlagsConnectionRequired) != 0);
  BOOL isNetworkReachable = (isReachable && !needsConnection);

  if (!isNetworkReachable) {
    return @"none";
  } else if ((flags & kSCNetworkReachabilityFlagsIsWWAN) != 0) {
    return @"wwan";
  } else {
    return @"wifi";
  }
}

@end
