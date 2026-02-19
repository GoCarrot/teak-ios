#import <XCTest/XCTest.h>

#import "../../Teak/TeakPushState.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Re-expose internal pushState property for testing
@interface Teak ()
@property (strong, nonatomic) TeakPushState* _Nonnull pushState;
@end

// Helper to create completed NSInvocationOperations with a known result
@interface TeakStateReturner : NSObject
@property (strong, nonatomic) id stateToReturn;
- (id)returnState;
@end

@implementation TeakStateReturner
- (id)returnState {
  return self.stateToReturn;
}
@end

@interface NotificationSettingsTests : XCTestCase
@end

@implementation NotificationSettingsTests

#pragma mark - Helpers

- (NSInvocationOperation*)completedOperationReturning:(TeakState*)state {
  TeakStateReturner* returner = [TeakStateReturner new];
  returner.stateToReturn = state;
  NSInvocationOperation* op = [[NSInvocationOperation alloc] initWithTarget:returner
                                                                   selector:@selector(returnState)
                                                                     object:nil];
  [op start];
  return op;
}

- (Teak*)teakWithMockedPushState:(TeakState*)state {
  Teak* teak = [[Teak alloc] init];
  TeakPushState* mockPushState = mock([TeakPushState class]);
  [given([mockPushState currentPushState]) willReturn:[self completedOperationReturning:state]];
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
