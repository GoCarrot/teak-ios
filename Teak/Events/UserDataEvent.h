#import "TeakEvent.h"
#import "TeakChannelStatus.h"

@interface UserDataEvent : TeakEvent
@property (strong, nonatomic, readonly) NSDictionary* _Nonnull additionalData;
@property (strong, nonatomic, readonly) TeakChannelStatus* _Nonnull emailStatus;
@property (strong, nonatomic, readonly) TeakChannelStatus* _Nonnull pushStatus;
@property (strong, nonatomic, readonly) TeakChannelStatus* _Nonnull smsStatus;
@property (strong, nonatomic, readonly) NSDictionary* _Nonnull pushRegistration;

- (NSDictionary* _Nonnull)toDictionary;

+ (void)userDataReceived:(NSDictionary* _Nonnull)additionalData emailStatus:(TeakChannelStatus* _Nonnull)emailStatus pushStatus:(TeakChannelStatus* _Nonnull)pushStatus smsStatus:(TeakChannelStatus* _Nonnull)smsStatus pushRegistration:(NSDictionary* _Nonnull)pushRegistration;
@end
