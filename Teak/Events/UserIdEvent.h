#import "TeakEvent.h"

@interface UserIdEvent : TeakEvent
@property (strong, nonatomic, readonly) NSString* _Nonnull userId;
@property (strong, nonatomic, readonly) NSArray* _Nonnull optOut;
@property (strong, nonatomic, readonly) NSString* _Nullable email;

+ (void)userIdentified:(nonnull NSString*)userId withOptOutList:(nonnull NSArray*)optOut andEmail:(nullable NSString*)email;
@end
