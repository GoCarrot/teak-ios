#import "UserDataEvent.h"

@interface UserDataEvent ()
@property (strong, nonatomic, readwrite) NSDictionary* _Nonnull additionalData;
@property (strong, nonatomic, readwrite) NSString* optOutEmail;
@property (strong, nonatomic, readwrite) NSString* optOutPush;
@property (strong, nonatomic, readwrite) NSDictionary* _Nonnull pushRegistration;
@end

@implementation UserDataEvent

- (NSDictionary*)toDictionary {
  return @{
    @"optOutEmail" : self.optOutEmail,
    @"optOutPush" : self.optOutPush,
    @"additionalData" : self.additionalData ? self.additionalData : [NSNull null],
    @"pushRegistration" : self.pushRegistration ? self.pushRegistration : [NSNull null]
  };
}

+ (void)userDataReceived:(NSDictionary*)additionalData optOutEmail:(NSString*)optOutEmail optOutPush:(NSString*)optOutPush pushRegistration:(NSDictionary*)pushRegistration {
  UserDataEvent* event = [[UserDataEvent alloc] initWithType:UserData];
  event.additionalData = additionalData;
  event.optOutEmail = optOutEmail ? optOutEmail : (NSString*)[NSNull null];
  event.optOutPush = optOutPush ? optOutPush : (NSString*)[NSNull null];
  [TeakEvent postEvent:event];
  event.pushRegistration = pushRegistration;
}
@end
