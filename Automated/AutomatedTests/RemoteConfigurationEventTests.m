#import <XCTest/XCTest.h>

#import "RemoteConfigurationEvent.h"
#import "TeakDeviceConfiguration.h"
#import "TeakRemoteConfiguration.h"
#import "TeakChannelCategory.h"

@import OCHamcrest;
@import OCMockito;

@interface TeakRemoteConfiguration (RequestTimeoutTest)
- (void)applyRequestTimeoutFromReply:(NSDictionary*)reply;
@end

@interface RemoteConfigurationEventTests : XCTestCase
@end

@implementation RemoteConfigurationEventTests

#pragma mark - request_timeout_ms

// Runs the same code the settings.json callback runs on its reply.
- (NSTimeInterval)timeoutAfterSettingsReply:(NSDictionary*)reply {
  TeakRemoteConfiguration* config = [[TeakRemoteConfiguration alloc] init];
  [config applyRequestTimeoutFromReply:reply];
  return config.requestTimeoutInterval;
}

- (void)testRequestTimeoutMsIsAppliedInSeconds {
  assertThatDouble([self timeoutAfterSettingsReply:@{@"request_timeout_ms" : @5000}], closeTo(5.0, 0.001));
  assertThatDouble([self timeoutAfterSettingsReply:@{@"request_timeout_ms" : @300000}], closeTo(300.0, 0.001));
}

- (void)testRequestTimeoutKeepsDefaultForAbsentOrInvalidValues {
  NSArray* invalid = @[ [NSNull null], @"5000", @0, @-1, @(NAN), @(INFINITY), @YES, @{}, @[] ];
  for (id value in invalid) {
    assertThatDouble([self timeoutAfterSettingsReply:@{@"request_timeout_ms" : value}], closeTo(60.0, 0.001));
  }
  assertThatDouble([self timeoutAfterSettingsReply:@{}], closeTo(60.0, 0.001));
}

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
