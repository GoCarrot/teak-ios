#import "TeakEvent.h"

@interface UserDataEvent : TeakEvent
@property (strong, nonatomic, readonly) NSDictionary* _Nonnull additionalData;
@property (strong, nonatomic, readonly) NSString* optOutEmail;
@property (strong, nonatomic, readonly) NSString* optOutPush;

- (NSDictionary*)toDictionary;

+ (void)userDataReceived:(NSDictionary* _Nonnull)additionalData optOutEmail:(NSString*)optOutEmail optOutPush:(NSString*)optOutPush;
@end
