#import "UserDataEvent.h"

@interface UserDataEvent ()
@property (strong, nonatomic, readwrite) NSDictionary* _Nonnull additionalData;
@property (strong, nonatomic, readwrite) TeakChannelStatus* _Nonnull emailStatus;
@property (strong, nonatomic, readwrite) TeakChannelStatus* _Nonnull pushStatus;
@property (strong, nonatomic, readwrite) TeakChannelStatus* _Nonnull smsStatus;
@property (strong, nonatomic, readwrite) NSDictionary* _Nonnull pushRegistration;
@end

@implementation UserDataEvent

- (NSDictionary*)toDictionary {
  return @{
    @"emailStatus" : self.emailStatus,
    @"pushStatus" : self.pushStatus,
    @"smsStatus" : self.smsStatus,
    @"additionalData" : self.additionalData ? self.additionalData : [NSNull null],
    @"pushRegistration" : self.pushRegistration ? self.pushRegistration : [NSNull null]
  };
}

+ (void)userDataReceived:(NSDictionary*)additionalData emailStatus:(TeakChannelStatus*)emailStatus pushStatus:(TeakChannelStatus*)pushStatus smsStatus:(TeakChannelStatus*)smsStatus pushRegistration:(NSDictionary*)pushRegistration {
  UserDataEvent* event = [[UserDataEvent alloc] initWithType:UserData];
  event.additionalData = additionalData;
  event.emailStatus = emailStatus;
  event.pushStatus = pushStatus;
  event.smsStatus = smsStatus;
  [TeakEvent postEvent:event];
  event.pushRegistration = pushRegistration;
}
@end
