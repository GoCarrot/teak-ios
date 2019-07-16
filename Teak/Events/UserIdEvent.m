#import "UserIdEvent.h"

@interface UserIdEvent ()
@property (strong, nonatomic, readwrite) NSString* _Nonnull userId;
@property (strong, nonatomic, readwrite) NSArray* _Nonnull optOut;
@property (strong, nonatomic, readwrite) NSString* _Nullable email;
@end

@implementation UserIdEvent

+ (void)userIdentified:(NSString*)userId withOptOutList:(NSArray*)optOut andEmail:(nullable NSString*)email {
  UserIdEvent* event = [[UserIdEvent alloc] initWithType:UserIdentified];
  event.userId = userId;
  event.optOut = optOut;
  event.email = email;
  [TeakEvent postEvent:event];
}
@end
