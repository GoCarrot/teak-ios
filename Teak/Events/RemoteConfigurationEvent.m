#import "RemoteConfigurationEvent.h"
#import "TeakChannelCategory.h"
#import "TeakDeviceConfiguration.h"
#import "TeakHelpers.h"

@interface RemoteConfigurationEvent ()
@property (strong, nonatomic, readwrite) TeakRemoteConfiguration* _Nonnull remoteConfiguration;
@property (strong, nonatomic, readwrite) TeakDeviceConfiguration* _Nonnull deviceConfiguration;
@end

@implementation RemoteConfigurationEvent

+ (void)remoteConfigurationReady:(TeakRemoteConfiguration* _Nonnull)remoteConfiguration deviceConfiguration:(TeakDeviceConfiguration* _Nonnull)deviceConfiguration {
  RemoteConfigurationEvent* event = [[RemoteConfigurationEvent alloc] initWithType:RemoteConfigurationReady];
  event.remoteConfiguration = remoteConfiguration;
  event.deviceConfiguration = deviceConfiguration;
  [TeakEvent postEvent:event];
}

-(nonnull NSDictionary*)appFacingConfiguration {
  NSMutableArray* serializedCategories = [[NSMutableArray alloc] init];
  for(TeakChannelCategory* category in self.remoteConfiguration.channelCategories) {
    [serializedCategories addObject:[category toDictionary]];
  }
  return @{
    @"channelCategories": serializedCategories,
    @"deviceId": TeakValueOrNSNull(self.deviceConfiguration.deviceId)
  };
}
@end
