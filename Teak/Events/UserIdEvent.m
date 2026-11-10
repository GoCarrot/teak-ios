#import "UserIdEvent.h"
#import "UserIdEvent+Internal.h"

@implementation UserIdEvent

+ (void)userIdentified:(nonnull NSString*)userId withConfiguration:(nonnull TeakUserConfiguration*)userConfiguration {
  UserIdEvent* event = [[UserIdEvent alloc] initWithType:UserIdentified];
  event.userId = userId;
  event.userConfiguration = userConfiguration;
  [TeakEvent postEvent:event];
}
@end
