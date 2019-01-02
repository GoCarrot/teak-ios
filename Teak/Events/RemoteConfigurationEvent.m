#import "RemoteConfigurationEvent.h"

@interface RemoteConfigurationEvent ()
@property (strong, nonatomic, readwrite) TeakRemoteConfiguration* _Nonnull remoteConfiguration;
@end

@implementation RemoteConfigurationEvent

+ (void)remoteConfigurationReady:(TeakRemoteConfiguration* _Nonnull)remoteConfiguration {
  RemoteConfigurationEvent* event = [[RemoteConfigurationEvent alloc] initWithType:RemoteConfigurationReady];
  event.remoteConfiguration = remoteConfiguration;
  [TeakEvent postEvent:event];
}
@end
