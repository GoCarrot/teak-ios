#import <XCTest/XCTest.h>

#import "../../Teak/Events/RemoteConfigurationEvent.h"
#import "../../Teak/Configuration/TeakRemoteConfiguration.h"
#import "../../Teak/TeakChannelCategory.h"

@import OCHamcrest;
@import OCMockito;

@interface RemoteConfigurationEventTests : XCTestCase
@end

@implementation RemoteConfigurationEventTests

- (void)testAppFacingConfigurationIncludesDeviceId {
  NSString* expectedDeviceId = @"test-device-id-67890";

  TeakRemoteConfiguration* remoteConfig = mock([TeakRemoteConfiguration class]);
  [given([remoteConfig channelCategories]) willReturn:@[]];

  RemoteConfigurationEvent* event = [[RemoteConfigurationEvent alloc] initWithType:RemoteConfigurationReady];
  [event setValue:remoteConfig forKey:@"remoteConfiguration"];
  [event setValue:expectedDeviceId forKey:@"deviceId"];

  NSDictionary* config = [event appFacingConfiguration];

  assertThat(config[@"deviceId"], is(expectedDeviceId));
  assertThat(config[@"channelCategories"], is(notNilValue()));
}

- (void)testAppFacingConfigurationPreservesChannelCategories {
  NSString* deviceId = @"device-xyz";

  TeakRemoteConfiguration* remoteConfig = mock([TeakRemoteConfiguration class]);
  [given([remoteConfig channelCategories]) willReturn:@[]];

  RemoteConfigurationEvent* event = [[RemoteConfigurationEvent alloc] initWithType:RemoteConfigurationReady];
  [event setValue:remoteConfig forKey:@"remoteConfiguration"];
  [event setValue:deviceId forKey:@"deviceId"];

  NSDictionary* config = [event appFacingConfiguration];

  assertThat(config[@"channelCategories"], instanceOf([NSArray class]));
  assertThat(config[@"deviceId"], is(deviceId));
}

@end
