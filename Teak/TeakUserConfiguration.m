#import "TeakUserConfiguration.h"

@implementation TeakUserConfiguration

- (nonnull NSDictionary*)to_h {
  return @{
    @"email" : (self.email == nil ? [NSNull null] : self.email),
    @"facebook_id" : (self.facebookId == nil ? [NSNull null] : self.facebookId),
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    @"opt_out_facebook" : self.optOutFacebook ? @YES : @NO,
#pragma clang diagnostic pop
    @"opt_out_idfa" : self.optOutIdfa ? @YES : @NO,
    @"opt_out_push_key" : self.optOutPushKey ? @YES : @NO
  };
}

- (id)copyWithZone:(NSZone*)zone {
  TeakUserConfiguration* copy = [[[self class] alloc] init];

  if (copy) {
    copy.email = [self.email copy];
    copy.facebookId = [self.facebookId copy];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    copy.optOutFacebook = self.optOutFacebook;
#pragma clang diagnostic pop
    copy.optOutIdfa = self.optOutIdfa;
    copy.optOutPushKey = self.optOutPushKey;
  }

  return copy;
}

@end
