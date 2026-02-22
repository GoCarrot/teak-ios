#import <XCTest/XCTest.h>

#import "UserDataEvent.h"
#import "TeakChannelStatus.h"
#import "TeakDeviceConfiguration.h"

@import OCHamcrest;
@import OCMockito;

@interface UserDataEventTests : XCTestCase
@end

@implementation UserDataEventTests

- (void)testToDictionaryIncludesDeviceId {
  NSString* expectedDeviceId = @"test-device-id-12345";

  TeakChannelStatus* emailStatus = mock([TeakChannelStatus class]);
  [given([emailStatus toDictionary]) willReturn:@{@"state" : @"unknown"}];
  TeakChannelStatus* pushStatus = mock([TeakChannelStatus class]);
  [given([pushStatus toDictionary]) willReturn:@{@"state" : @"unknown"}];
  TeakChannelStatus* smsStatus = mock([TeakChannelStatus class]);
  [given([smsStatus toDictionary]) willReturn:@{@"state" : @"unknown"}];

  TeakDeviceConfiguration* deviceConfig = mock([TeakDeviceConfiguration class]);
  [given([deviceConfig deviceId]) willReturn:expectedDeviceId];

  NSDictionary* additionalData = @{};
  NSDictionary* pushRegistration = (NSDictionary*)[NSNull null];

  UserDataEvent* event = [[UserDataEvent alloc] initWithType:UserData];
  [event setValue:additionalData forKey:@"additionalData"];
  [event setValue:emailStatus forKey:@"emailStatus"];
  [event setValue:pushStatus forKey:@"pushStatus"];
  [event setValue:smsStatus forKey:@"smsStatus"];
  [event setValue:pushRegistration forKey:@"pushRegistration"];
  [event setValue:deviceConfig forKey:@"deviceConfiguration"];

  NSDictionary* dict = [event toDictionary];

  assertThat(dict[@"deviceId"], is(expectedDeviceId));
  assertThat(dict[@"emailStatus"], is(notNilValue()));
  assertThat(dict[@"pushStatus"], is(notNilValue()));
  assertThat(dict[@"smsStatus"], is(notNilValue()));
}

- (void)testToDictionaryPreservesExistingFields {
  NSString* deviceId = @"device-abc";

  TeakChannelStatus* emailStatus = mock([TeakChannelStatus class]);
  NSDictionary* emailDict = @{@"state" : @"opted_in"};
  [given([emailStatus toDictionary]) willReturn:emailDict];

  TeakChannelStatus* pushStatus = mock([TeakChannelStatus class]);
  NSDictionary* pushDict = @{@"state" : @"opted_out"};
  [given([pushStatus toDictionary]) willReturn:pushDict];

  TeakChannelStatus* smsStatus = mock([TeakChannelStatus class]);
  NSDictionary* smsDict = @{@"state" : @"unknown"};
  [given([smsStatus toDictionary]) willReturn:smsDict];

  TeakDeviceConfiguration* deviceConfig = mock([TeakDeviceConfiguration class]);
  [given([deviceConfig deviceId]) willReturn:deviceId];

  NSDictionary* additionalData = @{@"key" : @"value"};
  NSDictionary* pushRegistration = @{@"apns" : @"token123"};

  UserDataEvent* event = [[UserDataEvent alloc] initWithType:UserData];
  [event setValue:additionalData forKey:@"additionalData"];
  [event setValue:emailStatus forKey:@"emailStatus"];
  [event setValue:pushStatus forKey:@"pushStatus"];
  [event setValue:smsStatus forKey:@"smsStatus"];
  [event setValue:pushRegistration forKey:@"pushRegistration"];
  [event setValue:deviceConfig forKey:@"deviceConfiguration"];

  NSDictionary* dict = [event toDictionary];

  assertThat(dict[@"emailStatus"], is(emailDict));
  assertThat(dict[@"pushStatus"], is(pushDict));
  assertThat(dict[@"smsStatus"], is(smsDict));
  assertThat(dict[@"additionalData"], is(additionalData));
  assertThat(dict[@"pushRegistration"], is(pushRegistration));
  assertThat(dict[@"deviceId"], is(deviceId));
}

@end
