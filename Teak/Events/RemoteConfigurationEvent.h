#import "TeakEvent.h"
#import "TeakRemoteConfiguration.h"

@interface RemoteConfigurationEvent : TeakEvent
@property (strong, nonatomic, readonly) TeakRemoteConfiguration* _Nonnull remoteConfiguration;
@property (strong, nonatomic, readonly) NSString* _Nonnull deviceId;

+ (void)remoteConfigurationReady:(TeakRemoteConfiguration* _Nonnull)remoteConfiguration deviceId:(NSString* _Nonnull)deviceId;
- (nonnull NSDictionary*)appFacingConfiguration;
@end
