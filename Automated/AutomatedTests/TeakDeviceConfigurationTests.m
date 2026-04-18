#import <XCTest/XCTest.h>

#import "PushRegistrationEvent.h"
#import "TeakDeviceConfiguration.h"
#import "TeakEvent.h"

@import OCHamcrest;
@import OCMockito;

@interface PushRegistrationEvent (Testing)
@property (strong, nonatomic, readwrite) NSString* _Nullable token;
@end

@interface TeakDeviceConfigurationTests : XCTestCase
@end

@implementation TeakDeviceConfigurationTests

#pragma mark - Initial state

- (void)testLiveActivityPushToStartTokenInitializesToEmptyString {
  TeakDeviceConfiguration* config = [[TeakDeviceConfiguration alloc] init];
  assertThat(config.liveActivityPushToStartToken, is(@""));
}

#pragma mark - handleEvent

- (void)testHandlingLiveActivityPushToStartRegisteredUpdatesProperty {
  TeakDeviceConfiguration* config = [[TeakDeviceConfiguration alloc] init];

  PushRegistrationEvent* event = [[PushRegistrationEvent alloc] initWithType:LiveActivityPushToStartRegistered];
  event.token = @"abcdef0123456789";
  [config handleEvent:event];

  assertThat(config.liveActivityPushToStartToken, is(@"abcdef0123456789"));
}

- (void)testHandlingLiveActivityPushToStartRegisteredDoesNotUpdateApnsPushToken {
  TeakDeviceConfiguration* config = [[TeakDeviceConfiguration alloc] init];

  PushRegistrationEvent* apnsEvent = [[PushRegistrationEvent alloc] initWithType:PushRegistered];
  apnsEvent.token = @"apns-token";
  [config handleEvent:apnsEvent];

  PushRegistrationEvent* ptsEvent = [[PushRegistrationEvent alloc] initWithType:LiveActivityPushToStartRegistered];
  ptsEvent.token = @"pts-token";
  [config handleEvent:ptsEvent];

  assertThat(config.pushToken, is(@"apns-token"));
  assertThat(config.liveActivityPushToStartToken, is(@"pts-token"));
}

- (void)testHandlingPushRegisteredDoesNotUpdateLiveActivityPushToStartToken {
  TeakDeviceConfiguration* config = [[TeakDeviceConfiguration alloc] init];

  PushRegistrationEvent* apnsEvent = [[PushRegistrationEvent alloc] initWithType:PushRegistered];
  apnsEvent.token = @"apns-token";
  [config handleEvent:apnsEvent];

  assertThat(config.liveActivityPushToStartToken, is(@""));
}

- (void)testTokenRotationUpdatesStoredValue {
  TeakDeviceConfiguration* config = [[TeakDeviceConfiguration alloc] init];

  PushRegistrationEvent* firstEvent = [[PushRegistrationEvent alloc] initWithType:LiveActivityPushToStartRegistered];
  firstEvent.token = @"first-token";
  [config handleEvent:firstEvent];
  assertThat(config.liveActivityPushToStartToken, is(@"first-token"));

  PushRegistrationEvent* rotatedEvent = [[PushRegistrationEvent alloc] initWithType:LiveActivityPushToStartRegistered];
  rotatedEvent.token = @"second-token";
  [config handleEvent:rotatedEvent];
  assertThat(config.liveActivityPushToStartToken, is(@"second-token"));
}

- (void)testSameTokenTwiceDoesNotChangeValue {
  TeakDeviceConfiguration* config = [[TeakDeviceConfiguration alloc] init];

  PushRegistrationEvent* firstEvent = [[PushRegistrationEvent alloc] initWithType:LiveActivityPushToStartRegistered];
  firstEvent.token = @"same-token";
  [config handleEvent:firstEvent];

  PushRegistrationEvent* secondEvent = [[PushRegistrationEvent alloc] initWithType:LiveActivityPushToStartRegistered];
  secondEvent.token = @"same-token";
  [config handleEvent:secondEvent];

  assertThat(config.liveActivityPushToStartToken, is(@"same-token"));
}

#pragma mark - to_h

- (void)testToHIncludesLiveActivityPushToStartKeyUnderPushRegistration {
  TeakDeviceConfiguration* config = [[TeakDeviceConfiguration alloc] init];

  PushRegistrationEvent* event = [[PushRegistrationEvent alloc] initWithType:LiveActivityPushToStartRegistered];
  event.token = @"live-activity-token";
  [config handleEvent:event];

  NSDictionary* dict = [config to_h];
  assertThat(dict[@"pushRegistration"][@"live_activity_push_to_start_key"], is(@"live-activity-token"));
}

- (void)testToHIncludesLiveActivityPushToStartKeyAlongsideApnsPushKey {
  TeakDeviceConfiguration* config = [[TeakDeviceConfiguration alloc] init];

  PushRegistrationEvent* apnsEvent = [[PushRegistrationEvent alloc] initWithType:PushRegistered];
  apnsEvent.token = @"apns-token";
  [config handleEvent:apnsEvent];

  PushRegistrationEvent* ptsEvent = [[PushRegistrationEvent alloc] initWithType:LiveActivityPushToStartRegistered];
  ptsEvent.token = @"pts-token";
  [config handleEvent:ptsEvent];

  NSDictionary* pushRegistration = [config to_h][@"pushRegistration"];
  assertThat(pushRegistration[@"apns_push_key"], is(@"apns-token"));
  assertThat(pushRegistration[@"live_activity_push_to_start_key"], is(@"pts-token"));
}

@end
