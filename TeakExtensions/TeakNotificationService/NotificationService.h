//
//  NotificationService.h
//  TeakNotificationService
//
//  Created by Pat Wilson on 11/1/17.
//  Copyright © 2017 GoCarrot Inc. All rights reserved.
//

#import <UserNotifications/UserNotifications.h>

@interface NotificationService : UNNotificationServiceExtension
- (void)serviceExtensionTimeWillExpire;
@end
