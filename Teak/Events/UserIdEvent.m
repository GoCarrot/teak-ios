#import "UserIdEvent.h"

@interface UserIdEvent ()
@property (strong, nonatomic, readwrite) NSString* _Nonnull userId;
@property (strong, nonatomic, readwrite) NSArray* _Nonnull optOut;
@end

@implementation UserIdEvent

+ (void)userIdentified:(NSString*)userId withOptOutList:(NSArray*)optOut {
  UserIdEvent* event = [[UserIdEvent alloc] initWithType:UserIdentified];
  event.userId = userId;
  event.optOut = optOut;
  [TeakEvent postEvent:event];
}
@end
