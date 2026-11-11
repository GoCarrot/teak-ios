#import <XCTest/XCTest.h>
#import "AtomicPropertyAssertions.h"
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

#pragma mark - Atomicity

// pushToken/liveActivityPushToStartToken/advertisingIdentifier/notificationDisplayEnabled are all
// reassigned from a writer thread other than TeakSession's operation queue, which reads them while
// building the identify payload (see RaceTripwireTests.m for the dynamic use-after-free repro
// backing these four). A cheap permanent guard, complementary to the dynamic repro.
- (void)testPushTokenIsAtomic {
  XCTAssertTrue(isAtomicProperty([TeakDeviceConfiguration class], "pushToken"),
                 @"TeakDeviceConfiguration.pushToken must stay atomic — reassigned on the event-processing queue while read by TeakSession's operation queue");
}

- (void)testLiveActivityPushToStartTokenIsAtomic {
  XCTAssertTrue(isAtomicProperty([TeakDeviceConfiguration class], "liveActivityPushToStartToken"),
                 @"TeakDeviceConfiguration.liveActivityPushToStartToken must stay atomic — same cross-thread reassignment hazard as pushToken");
}

- (void)testAdvertisingIdentifierIsAtomic {
  XCTAssertTrue(isAtomicProperty([TeakDeviceConfiguration class], "advertisingIdentifier"),
                 @"TeakDeviceConfiguration.advertisingIdentifier must stay atomic — reassigned from init/the event queue/a main-queue retry while read by TeakSession's operation queue");
}

- (void)testNotificationDisplayEnabledIsAtomic {
  XCTAssertTrue(isAtomicProperty([TeakDeviceConfiguration class], "notificationDisplayEnabled"),
                 @"TeakDeviceConfiguration.notificationDisplayEnabled must stay atomic — reassigned on the pushState operation queue's completion block while read by TeakSession's operation queue");
}

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
