#import <UserNotifications/UserNotifications.h>

@interface TeakNotificationServiceCore : UNNotificationServiceExtension
- (void)serviceExtensionTimeWillExpire;
@end

@interface TeakNotificationService : TeakNotificationServiceCore
- (void)serviceExtensionTimeWillExpire;
@end
