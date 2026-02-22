#import <XCTest/XCTest.h>

#import "../../Teak/TeakPushState.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Re-expose internal pushState property for testing
@interface Teak ()
@property (strong, nonatomic) TeakPushState* _Nonnull pushState;
@end

@interface NotificationSettingsTests : XCTestCase
@end

@implementation NotificationSettingsTests

#pragma mark - Helpers

// [[Teak alloc] init] bypasses initWithApplicationId:andSecret: and creates a
// bare instance with nil properties. This is safe for unit testing because we
// only set the properties under test. Production code must use [Teak sharedInstance].
- (Teak*)teakWithMockedPushState:(TeakState*)state {
  Teak* teak = [[Teak alloc] init];
  TeakPushState* mockPushState = mock([TeakPushState class]);
  [given([mockPushState cachedPushState]) willReturn:state];
  teak.pushState = mockPushState;
  return teak;
}

#pragma mark - canOpenNotificationSettings returns NO when NotDetermined

- (void)testCanOpenNotificationSettingsReturnsFalseWhenNotDetermined {
  Teak* teak = [self teakWithMockedPushState:[TeakPushState NotDetermined]];

  XCTAssertFalse([teak canOpenNotificationSettings],
                 @"canOpenNotificationSettings should return NO when push state is NotDetermined");
}

#pragma mark - canOpenNotificationSettings returns YES for all other states

- (void)testCanOpenNotificationSettingsReturnsTrueWhenAuthorized {
  Teak* teak = [self teakWithMockedPushState:[TeakPushState Authorized]];

  XCTAssertTrue([teak canOpenNotificationSettings],
                @"canOpenNotificationSettings should return YES when push state is Authorized");
}

- (void)testCanOpenNotificationSettingsReturnsTrueWhenDenied {
  Teak* teak = [self teakWithMockedPushState:[TeakPushState Denied]];

  XCTAssertTrue([teak canOpenNotificationSettings],
                @"canOpenNotificationSettings should return YES when push state is Denied");
}

- (void)testCanOpenNotificationSettingsReturnsTrueWhenProvisional {
  Teak* teak = [self teakWithMockedPushState:[TeakPushState Provisional]];

  XCTAssertTrue([teak canOpenNotificationSettings],
                @"canOpenNotificationSettings should return YES when push state is Provisional");
}

@end
