#import "UserIdEvent.h"

@interface UserIdEvent ()
@property (strong, nonatomic, readwrite) NSString* _Nonnull userId;
@property (strong, nonatomic, readwrite) TeakUserConfiguration* _Nonnull userConfiguration;
@end

@implementation UserIdEvent

+ (void)userIdentified:(nonnull NSString*)userId withConfiguration:(nonnull TeakUserConfiguration*)userConfiguration {
  UserIdEvent* event = [[UserIdEvent alloc] initWithType:UserIdentified];
  event.userId = userId;
  event.userConfiguration = userConfiguration;
  [TeakEvent postEvent:event];
}
@end
