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

@end
