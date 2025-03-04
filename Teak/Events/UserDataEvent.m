#import "UserDataEvent.h"
#import "TeakHelpers.h"

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
    @"emailStatus" : [self.emailStatus toDictionary],
    @"pushStatus" : [self.pushStatus toDictionary],
    @"smsStatus" : [self.smsStatus toDictionary],
    @"additionalData" : TeakValueOrNSNull(self.additionalData),
    @"pushRegistration" : TeakValueOrNSNull(self.pushRegistration),
  };
}

+ (void)userDataReceived:(NSDictionary* _Nonnull)additionalData emailStatus:(TeakChannelStatus* _Nonnull)emailStatus pushStatus:(TeakChannelStatus* _Nonnull)pushStatus smsStatus:(TeakChannelStatus* _Nonnull)smsStatus pushRegistration:(NSDictionary* _Nonnull)pushRegistration {
  UserDataEvent* event = [[UserDataEvent alloc] initWithType:UserData];
  event.additionalData = additionalData;
  event.emailStatus = emailStatus;
  event.pushStatus = pushStatus;
  event.smsStatus = smsStatus;
  event.pushRegistration = pushRegistration;
  [TeakEvent postEvent:event];
}
@end
