//
//  NotificationService.m
//  NotificationServiceTest
//
//  Created by Pat Wilson on 3/1/17.
//  Copyright © 2017 GoCarrot Inc. All rights reserved.
//

#import "NotificationService.h"

@interface NotificationService ()

@property (nonatomic, strong) void (^contentHandler)(UNNotificationContent *contentToDeliver);
@property (nonatomic, strong) UNMutableNotificationContent *bestAttemptContent;

@end

@implementation NotificationService

- (void)didReceiveNotificationRequest:(UNNotificationRequest *)request withContentHandler:(void (^)(UNNotificationContent * _Nonnull))contentHandler {
   self.contentHandler = contentHandler;
   self.bestAttemptContent = [request.content mutableCopy];

   // Modify the notification content here...
   self.bestAttemptContent.title = [request.content.userInfo objectForKey:@"title"];

   NSString* remoteFile = [request.content.userInfo objectForKey:@"imageAssetA"];
   NSString* fileExtension = [NSString stringWithFormat:@".%@", [remoteFile pathExtension]];
   NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
   [[session downloadTaskWithURL:[NSURL URLWithString:remoteFile]
              completionHandler:^(NSURL *temporaryFileLocation, NSURLResponse *response, NSError *error) {
                 if (error != nil) {
                    NSLog(@"%@", error.localizedDescription);
                 } else {
                    NSFileManager *fileManager = [NSFileManager defaultManager];
                    NSURL *localURL = [NSURL fileURLWithPath:[temporaryFileLocation.path stringByAppendingString:fileExtension]];
                    [fileManager moveItemAtURL:temporaryFileLocation toURL:localURL error:&error];
                    NSError *attachmentError = nil;
                    UNNotificationAttachment* attachment = [UNNotificationAttachment attachmentWithIdentifier:@"" URL:localURL options:nil error:&attachmentError];
                    if (attachmentError) {
                       NSLog(@"%@", attachmentError.localizedDescription);
                    } else {
                       self.bestAttemptContent.attachments = [NSArray arrayWithObject:attachment];
                    }
                 }

                 self.contentHandler(self.bestAttemptContent);
              }] resume];
}

- (void)serviceExtensionTimeWillExpire {
   // Called just before the extension will be terminated by the system.
   // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
   self.contentHandler(self.bestAttemptContent);
}

@end
