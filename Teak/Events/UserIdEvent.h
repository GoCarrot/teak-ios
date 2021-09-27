#import "TeakEvent.h"
#import "TeakUserConfiguration.h"

@interface UserIdEvent : TeakEvent
@property (strong, nonatomic, readonly) NSString* _Nonnull userId;
@property (strong, nonatomic, readonly) TeakUserConfiguration* _Nonnull userConfiguration;

+ (void)userIdentified:(nonnull NSString*)userId withConfiguration:(nonnull TeakUserConfiguration*)userConfiguration;
@end
