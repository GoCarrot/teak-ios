#import "TeakEvent.h"

@interface UserIdEvent : TeakEvent
@property (strong, nonatomic, readonly) NSString* _Nonnull userId;
@property (strong, nonatomic, readonly) NSArray* _Nonnull optOut;

+ (void)userIdentified:(nonnull NSString*)userId withOptOutList:(nonnull NSArray*)optOut;
@end
