#import <XCTest/XCTest.h>

#import "../../Teak/Events/UserDataEvent.h"
#import "../../Teak/Core/TeakChannelStatus.h"

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

  NSDictionary* additionalData = @{};
  NSDictionary* pushRegistration = (NSDictionary*)[NSNull null];

  UserDataEvent* event = [[UserDataEvent alloc] initWithType:UserData];
  [event setValue:additionalData forKey:@"additionalData"];
  [event setValue:emailStatus forKey:@"emailStatus"];
  [event setValue:pushStatus forKey:@"pushStatus"];
  [event setValue:smsStatus forKey:@"smsStatus"];
  [event setValue:pushRegistration forKey:@"pushRegistration"];
  [event setValue:expectedDeviceId forKey:@"deviceId"];

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

  NSDictionary* additionalData = @{@"key" : @"value"};
  NSDictionary* pushRegistration = @{@"apns" : @"token123"};

  UserDataEvent* event = [[UserDataEvent alloc] initWithType:UserData];
  [event setValue:additionalData forKey:@"additionalData"];
  [event setValue:emailStatus forKey:@"emailStatus"];
  [event setValue:pushStatus forKey:@"pushStatus"];
  [event setValue:smsStatus forKey:@"smsStatus"];
  [event setValue:pushRegistration forKey:@"pushRegistration"];
  [event setValue:deviceId forKey:@"deviceId"];

  NSDictionary* dict = [event toDictionary];

  assertThat(dict[@"emailStatus"], is(emailDict));
  assertThat(dict[@"pushStatus"], is(pushDict));
  assertThat(dict[@"smsStatus"], is(smsDict));
  assertThat(dict[@"additionalData"], is(additionalData));
  assertThat(dict[@"pushRegistration"], is(pushRegistration));
  assertThat(dict[@"deviceId"], is(deviceId));
}

@end
