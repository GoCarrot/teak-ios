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

- (void)testAppFacingConfigurationSerializesChannelCategories {
  TeakChannelCategory* category = [[TeakChannelCategory alloc] initWithId:@"promo" name:@"Promotions" andDescription:@"Deals and offers"];
  NSDictionary* expectedCategoryDict = [category toDictionary];

  TeakRemoteConfiguration* remoteConfig = mock([TeakRemoteConfiguration class]);
  [given([remoteConfig channelCategories]) willReturn:@[category]];

  TeakDeviceConfiguration* deviceConfig = mock([TeakDeviceConfiguration class]);
  [given([deviceConfig deviceId]) willReturn:@"device-xyz"];

  RemoteConfigurationEvent* event = [[RemoteConfigurationEvent alloc] initWithType:RemoteConfigurationReady];
  [event setValue:remoteConfig forKey:@"remoteConfiguration"];
  [event setValue:deviceConfig forKey:@"deviceConfiguration"];

  NSDictionary* config = [event appFacingConfiguration];

  NSArray* categories = config[@"channelCategories"];
  assertThat(categories, hasCountOf(1));
  assertThat(categories[0], is(expectedCategoryDict));
}

- (void)testAppFacingConfigurationWithNilDeviceIdProducesNSNull {
  TeakRemoteConfiguration* remoteConfig = mock([TeakRemoteConfiguration class]);
  [given([remoteConfig channelCategories]) willReturn:@[]];

  TeakDeviceConfiguration* deviceConfig = mock([TeakDeviceConfiguration class]);
  [given([deviceConfig deviceId]) willReturn:nil];

  RemoteConfigurationEvent* event = [[RemoteConfigurationEvent alloc] initWithType:RemoteConfigurationReady];
  [event setValue:remoteConfig forKey:@"remoteConfiguration"];
  [event setValue:deviceConfig forKey:@"deviceConfiguration"];

  NSDictionary* config = [event appFacingConfiguration];

  assertThat(config[@"deviceId"], is([NSNull null]));
}

@end
