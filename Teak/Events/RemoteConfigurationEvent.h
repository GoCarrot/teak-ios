#import "TeakEvent.h"
#import "TeakRemoteConfiguration.h"

@class TeakDeviceConfiguration;

@interface RemoteConfigurationEvent : TeakEvent
@property (strong, nonatomic, readonly) TeakRemoteConfiguration* _Nonnull remoteConfiguration;
@property (strong, nonatomic, readonly) TeakDeviceConfiguration* _Nonnull deviceConfiguration;

+ (void)remoteConfigurationReady:(TeakRemoteConfiguration* _Nonnull)remoteConfiguration deviceConfiguration:(TeakDeviceConfiguration* _Nonnull)deviceConfiguration;
- (nonnull NSDictionary*)appFacingConfiguration;
@end
