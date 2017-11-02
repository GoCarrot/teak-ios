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

  @try {
    NSDictionary* notification = request.content.userInfo[@"aps"];
    NSString* teakNotifId = notification[@"teakNotifId"];
    if ([teakNotifId length > 0]) {
      self.bestAttemptContent.title = [NSString stringWithFormat:@"%@", teakNotifId];
    }
  } @finally {
    self.contentHandler(self.bestAttemptContent);
  }
}

- (void)serviceExtensionTimeWillExpire {
  self.contentHandler(self.bestAttemptContent);
}

@end
