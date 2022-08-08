#import "UserDataEvent.h"

@interface UserDataEvent ()
@property (strong, nonatomic, readwrite) NSDictionary* _Nonnull additionalData;
@property (strong, nonatomic, readwrite) NSString* optOutEmail;
@property (strong, nonatomic, readwrite) NSString* optOutPush;
@end

@implementation UserDataEvent

- (NSDictionary*)toDictionary {
  return @{
    @"optOutEmail" : self.optOutEmail,
    @"optOutPush" : self.optOutPush,
    @"additionalData" : self.additionalData ? self.additionalData : [NSNull null]
  };
}

+ (void)userDataReceived:(NSDictionary*)additionalData optOutEmail:(NSString*)optOutEmail optOutPush:(NSString*)optOutPush {
  UserDataEvent* event = [[UserDataEvent alloc] initWithType:UserData];
  event.additionalData = additionalData;
  event.optOutEmail = optOutEmail ? optOutEmail : [NSNull null];
  event.optOutPush = optOutPush ? optOutPush : [NSNull null];
  [TeakEvent postEvent:event];
}
@end
