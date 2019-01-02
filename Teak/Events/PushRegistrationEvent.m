#import "PushRegistrationEvent.h"

@interface PushRegistrationEvent ()
@property (strong, nonatomic, readwrite) NSString* _Nullable token;
@end

@implementation PushRegistrationEvent
+ (void)registeredWithToken:(NSString* _Nonnull)token {
  PushRegistrationEvent* event = [[PushRegistrationEvent alloc] initWithType:PushRegistered];
  event.token = token;
  [TeakEvent postEvent:event];
}

+ (void)unRegistered {
  PushRegistrationEvent* event = [[PushRegistrationEvent alloc] initWithType:PushUnRegistered];
  [TeakEvent postEvent:event];
}
@end
