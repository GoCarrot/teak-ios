#import "FacebookAccessTokenEvent.h"

@interface FacebookAccessTokenEvent ()
@property (strong, nonatomic, readwrite) NSString* _Nonnull accessToken;
@end

@implementation FacebookAccessTokenEvent

+ (void)accessTokenUpdated:(NSString* _Nonnull)accessToken {
  FacebookAccessTokenEvent* event = [[FacebookAccessTokenEvent alloc] initWithType:FacebookAccessToken];
  event.accessToken = accessToken;
  [TeakEvent postEvent:event];
}

+ (NSString*)currentAccessToken {
  Class cls = NSClassFromString(@"FBSDKAccessToken");
  if (cls == nil) {
    return nil;
  }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
  return [[cls performSelector:sel_getUid("currentAccessToken")] performSelector:sel_getUid("tokenString")];
#pragma clang diagnostic pop
}

@end
