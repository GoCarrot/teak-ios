#import "TeakEvent.h"

@interface PushRegistrationEvent : TeakEvent
@property (strong, nonatomic, readonly) NSString* _Nullable token;

+ (void)registeredWithToken:(NSString* _Nonnull)token;
+ (void)unRegistered;
@end
