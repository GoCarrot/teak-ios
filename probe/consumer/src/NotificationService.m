#import "NotificationService.h"

@implementation NotificationService
- (void)didReceiveNotificationRequest:(UNNotificationRequest*)request withContentHandler:(void (^)(UNNotificationContent*))contentHandler {
  NSLog(@"PROBE-NSE: didReceiveNotificationRequest");
  [super didReceiveNotificationRequest:request
                    withContentHandler:^(UNNotificationContent* content) {
                      NSLog(@"PROBE-NSE: contentHandler fired");
                      contentHandler(content);
                    }];
}
@end
