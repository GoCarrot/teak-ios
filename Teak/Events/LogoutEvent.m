#import "LogoutEvent.h"

@implementation LogoutEvent

+ (void)logout {
  LogoutEvent* event = [[LogoutEvent alloc] initWithType:Logout];
  [TeakEvent postEvent:event];
}

@end
