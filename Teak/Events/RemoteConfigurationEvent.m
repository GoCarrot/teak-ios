#import "RemoteConfigurationEvent.h"
#import "TeakChannelCategory.h"

@interface RemoteConfigurationEvent ()
@property (strong, nonatomic, readwrite) TeakRemoteConfiguration* _Nonnull remoteConfiguration;
@end

@implementation RemoteConfigurationEvent

+ (void)remoteConfigurationReady:(TeakRemoteConfiguration* _Nonnull)remoteConfiguration {
  RemoteConfigurationEvent* event = [[RemoteConfigurationEvent alloc] initWithType:RemoteConfigurationReady];
  event.remoteConfiguration = remoteConfiguration;
  [TeakEvent postEvent:event];
}

-(nonnull NSDictionary*)appFacingConfiguration {
  NSMutableArray* serializedCategories = [[NSMutableArray alloc] init];
  for(TeakChannelCategory* category in self.remoteConfiguration.channelCategories) {
    [serializedCategories addObject:[category toDictionary]];
  }
  return @{
    @"channelCategories": serializedCategories
  };
}
@end
