#import "RemoteConfigurationEvent.h"
#import "TeakChannelCategory.h"

@interface RemoteConfigurationEvent ()
@property (strong, nonatomic, readwrite) TeakRemoteConfiguration* _Nonnull remoteConfiguration;
@property (strong, nonatomic, readwrite) NSString* _Nonnull deviceId;
@end

@implementation RemoteConfigurationEvent

+ (void)remoteConfigurationReady:(TeakRemoteConfiguration* _Nonnull)remoteConfiguration deviceId:(NSString* _Nonnull)deviceId {
  RemoteConfigurationEvent* event = [[RemoteConfigurationEvent alloc] initWithType:RemoteConfigurationReady];
  event.remoteConfiguration = remoteConfiguration;
  event.deviceId = deviceId;
  [TeakEvent postEvent:event];
}

-(nonnull NSDictionary*)appFacingConfiguration {
  NSMutableArray* serializedCategories = [[NSMutableArray alloc] init];
  for(TeakChannelCategory* category in self.remoteConfiguration.channelCategories) {
    [serializedCategories addObject:[category toDictionary]];
  }
  return @{
    @"channelCategories": serializedCategories,
    @"deviceId": self.deviceId
  };
}
@end
