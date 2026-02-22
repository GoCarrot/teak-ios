#import <XCTest/XCTest.h>

#import "RemoteConfigurationEvent.h"
#import "TeakDeviceConfiguration.h"
#import "TeakRemoteConfiguration.h"
#import "TeakChannelCategory.h"

@import OCHamcrest;
@import OCMockito;

@interface RemoteConfigurationEventTests : XCTestCase
@end

@implementation RemoteConfigurationEventTests

- (void)testAppFacingConfigurationIncludesDeviceId {
  NSString* expectedDeviceId = @"test-device-id-67890";

  TeakRemoteConfiguration* remoteConfig = mock([TeakRemoteConfiguration class]);
  [given([remoteConfig channelCategories]) willReturn:@[]];

  TeakDeviceConfiguration* deviceConfig = mock([TeakDeviceConfiguration class]);
  [given([deviceConfig deviceId]) willReturn:expectedDeviceId];

  RemoteConfigurationEvent* event = [[RemoteConfigurationEvent alloc] initWithType:RemoteConfigurationReady];
  [event setValue:remoteConfig forKey:@"remoteConfiguration"];
  [event setValue:deviceConfig forKey:@"deviceConfiguration"];

  NSDictionary* config = [event appFacingConfiguration];

  assertThat(config[@"deviceId"], is(expectedDeviceId));
  assertThat(config[@"channelCategories"], is(notNilValue()));
}

- (void)testAppFacingConfigurationPreservesChannelCategories {
  NSString* deviceId = @"device-xyz";

  TeakRemoteConfiguration* remoteConfig = mock([TeakRemoteConfiguration class]);
  [given([remoteConfig channelCategories]) willReturn:@[]];

  TeakDeviceConfiguration* deviceConfig = mock([TeakDeviceConfiguration class]);
  [given([deviceConfig deviceId]) willReturn:deviceId];

  RemoteConfigurationEvent* event = [[RemoteConfigurationEvent alloc] initWithType:RemoteConfigurationReady];
  [event setValue:remoteConfig forKey:@"remoteConfiguration"];
  [event setValue:deviceConfig forKey:@"deviceConfiguration"];

  NSDictionary* config = [event appFacingConfiguration];

  assertThat(config[@"channelCategories"], instanceOf([NSArray class]));
  assertThat(config[@"deviceId"], is(deviceId));
}

@end
