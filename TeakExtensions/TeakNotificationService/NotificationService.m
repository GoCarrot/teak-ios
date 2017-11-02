//
//  NotificationService.m
//  TeakNotificationService
//
//  Created by Pat Wilson on 11/1/17.
//  Copyright © 2017 GoCarrot Inc. All rights reserved.
//

#import "NotificationService.h"

@interface NotificationService ()

@property (nonatomic, strong) void (^contentHandler)(UNNotificationContent* contentToDeliver);
@property (nonatomic, strong) UNMutableNotificationContent* bestAttemptContent;

@end

@implementation NotificationService

/*
 final String teakUserId = bundle.getString("teakUserId", null);
 if (teakUserId != null) {
 final Session session = Session.getCurrentSessionOrNull();
 final TeakConfiguration teakConfiguration = TeakConfiguration.get();
 if (session != null) {
 HashMap<String, Object> payload = new HashMap<>();
 payload.put("app_id", teakConfiguration.appConfiguration.appId);
 payload.put("user_id", teakUserId);
 payload.put("platform_id", teakNotification.teakNotifId);
 if (teakNotification.teakNotifId == 0) {
 payload.put("impression", false);
 }
 
 asyncExecutor.execute(new Request("parsnip.gocarrot.com", "/notification_received", payload, session));
 }
 }
 */
- (void)didReceiveNotificationRequest:(UNNotificationRequest*)request withContentHandler:(void (^)(UNNotificationContent* _Nonnull))contentHandler {
  self.contentHandler = contentHandler;
  self.bestAttemptContent = [request.content mutableCopy];

  // Modify the notification content here...
  self.bestAttemptContent.title = [NSString stringWithFormat:@"%@ [modified]", self.bestAttemptContent.title];

  self.contentHandler(self.bestAttemptContent);
}

- (void)serviceExtensionTimeWillExpire {
  // Called just before the extension will be terminated by the system.
  // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
  self.contentHandler(self.bestAttemptContent);
}

@end
