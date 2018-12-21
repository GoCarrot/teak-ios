#import "TeakEvent.h"
#import "TeakRemoteConfiguration.h"

@interface RemoteConfigurationEvent : TeakEvent
@property (strong, nonatomic, readonly) TeakRemoteConfiguration* _Nonnull remoteConfiguration;

+ (void)remoteConfigurationReady:(TeakRemoteConfiguration* _Nonnull)remoteConfiguration;
@end
