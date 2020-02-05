#import "TeakEvent.h"

@interface FacebookAccessTokenEvent : TeakEvent

@property (strong, nonatomic, readonly) NSString* _Nonnull accessToken;

+ (void)accessTokenUpdated:(NSString* _Nonnull)accessToken;

+ (NSString*)currentAccessToken;

@end
