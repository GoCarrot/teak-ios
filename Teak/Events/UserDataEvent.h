#import "TeakEvent.h"

@interface UserDataEvent : TeakEvent
@property (strong, nonatomic, readonly) NSDictionary* _Nonnull additionalData;
@property (strong, nonatomic, readonly) NSString* _Nonnull optOutEmail;
@property (strong, nonatomic, readonly) NSString* _Nonnull optOutPush;

- (NSDictionary* _Nonnull)toDictionary;

+ (void)userDataReceived:(NSDictionary* _Nonnull)additionalData optOutEmail:(NSString* _Nonnull)optOutEmail optOutPush:(NSString* _Nonnull)optOutPush;
@end
