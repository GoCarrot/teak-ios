#import "TeakEvent.h"

@interface UserDataEvent : TeakEvent
@property (strong, nonatomic, readonly) NSDictionary* _Nonnull additionalData;
@property (nonatomic, readonly) BOOL optOutEmail;
@property (nonatomic, readonly) BOOL optOutPush;

- (NSDictionary*)toDictionary;

+ (void)userDataReceived:(NSDictionary* _Nonnull)additionalData optOutEmail:(BOOL)optOutEmail optOutPush:(BOOL)optOutPush;
@end
