#import "TeakUserConfiguration.h"

@implementation TeakUserConfiguration

- (nonnull NSDictionary*)to_h {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
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
#pragma clang diagnostic pop
}

- (id)copyWithZone:(NSZone*)zone {
  TeakUserConfiguration* copy = [[[self class] alloc] init];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
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
#pragma clang diagnostic pop
  return copy;
}

+ (TeakUserConfiguration*)fromDictionary:(NSDictionary*)dictionary {
  TeakUserConfiguration* config = [[TeakUserConfiguration alloc] init];
#define ASSIGN_STRING_OR_NIL(x) ((x == [NSNull null]) ? nil : [x stringValue])
#define ASSIGN_BOOL_OR_FALSE(x) ((x == [NSNull null]) ? NO : [x boolValue])
  config.email = ASSIGN_STRING_OR_NIL(dictionary[@"email"]);
  config.facebookId = ASSIGN_STRING_OR_NIL(dictionary[@"facebookId"]);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  config.optOutFacebook = ASSIGN_BOOL_OR_FALSE(dictionary[@"optOutFacebook"]);
#pragma clang diagnostic pop
  config.optOutIdfa = ASSIGN_BOOL_OR_FALSE(dictionary[@"optOutIdfa"]);
  config.optOutPushKey = ASSIGN_BOOL_OR_FALSE(dictionary[@"optOutPushKey"]);
#undef ASSIGN_STRING_OR_NIL
#undef ASSIGN_BOOL_OR_FALSE
  return config;
}

@end
