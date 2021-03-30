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

+ (NSString*)currentUserToken {
  // Start with trying to get the access token
  id authToken = [FacebookAccessTokenEvent currentAccessToken];

  // This will be nil in the case of limited login, or if there is no
  // Facebook SDK, or the user is simply not logged in with Facebook.
  if (authToken == nil) {
    // In which case, try getting the authentication token
    authToken = [FacebookAccessTokenEvent currentAuthenticationToken];
  }

  // If still nil, bail
  if (authToken == nil) {
    return nil;
  }

  // Otherwise return the token string
  SEL selector = sel_getUid("tokenString");
  IMP imp = [authToken methodForSelector:selector];
  NSString* (*func)(id, SEL) = (void*)imp;

  return func(authToken, selector);
}

+ (NSString*)currentAccessToken {
  Class cls = NSClassFromString(@"FBSDKAccessToken");
  if (cls == nil) {
    return nil;
  }

  SEL sel = NSSelectorFromString(@"currentAccessToken");
  NSInvocation* inv = [NSInvocation invocationWithMethodSignature:[cls methodSignatureForSelector:sel]];
  [inv setSelector:sel];
  [inv setTarget:cls];
  [inv invoke];

  void* temp;
  [inv getReturnValue:&temp];
  return (__bridge NSString*)temp;
}

+ (NSString*)currentAuthenticationToken {
  Class cls = NSClassFromString(@"FBSDKAuthenticationToken");
  if (cls == nil) {
    return nil;
  }

  SEL sel = NSSelectorFromString(@"currentAuthenticationToken");
  NSInvocation* inv = [NSInvocation invocationWithMethodSignature:[cls methodSignatureForSelector:sel]];
  [inv setSelector:sel];
  [inv setTarget:cls];
  [inv invoke];

  void* temp;
  [inv getReturnValue:&temp];
  return (__bridge id)temp;
}

@end
