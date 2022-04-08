#import "UserDataEvent.h"

@interface UserDataEvent ()
@property (strong, nonatomic, readwrite) NSDictionary* _Nonnull additionalData;
@property (nonatomic, readwrite) BOOL optOutEmail;
@property (nonatomic, readwrite) BOOL optOutPush;
@end

@implementation UserDataEvent

- (NSDictionary*)toDictionary {
  return @{
    @"optOutEmail" : [NSNumber numberWithBool:self.optOutEmail],
    @"optOutPush" : [NSNumber numberWithBool:self.optOutPush],
    @"additionalData" : self.additionalData ? self.additionalData : [NSNull null]
  };
}

+ (void)userDataReceived:(NSDictionary*)additionalData optOutEmail:(BOOL)optOutEmail optOutPush:(BOOL)optOutPush {
  UserDataEvent* event = [[UserDataEvent alloc] initWithType:UserData];
  event.additionalData = additionalData;
  event.optOutEmail = optOutEmail;
  event.optOutPush = optOutPush;
  [TeakEvent postEvent:event];
}
@end
