#import <XCTest/XCTest.h>

#import "TeakLog.h"
#import "TeakRemoteConfiguration.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Static method under test — re-exposed for the test target.
@interface TeakRemoteConfiguration (TestAccess)
+ (BOOL)validateClaimMode:(nullable NSString*)configuredClaimMode againstSupported:(nullable id)supportedClaimModes;
@end

// Re-expose internal log property so tests can wire a real TeakLog into the
// shared instance and observe TeakLog_w emissions through logListener.
@interface Teak ()
@property (strong, nonatomic) TeakLog* _Nonnull log;
@end

extern Teak* _teakSharedInstance;

@interface TeakRemoteConfigurationClaimModeTests : XCTestCase
@property (strong, nonatomic) Teak* previousSharedInstance;
@property (strong, nonatomic) Teak* teakMock;
@end

@implementation TeakRemoteConfigurationClaimModeTests

- (void)setUp {
  [super setUp];
  self.previousSharedInstance = _teakSharedInstance;

  self.teakMock = mock([Teak class]);
  [given([self.teakMock enableRemoteLogging]) willReturn:@NO];
  [given([self.teakMock enableDebugOutput]) willReturn:@NO];

  TeakLog* log = [[TeakLog alloc] initForTeak:self.teakMock withAppId:@"automated"];
  [given([self.teakMock log]) willReturn:log];

  _teakSharedInstance = self.teakMock;
}

- (void)tearDown {
  _teakSharedInstance = self.previousSharedInstance;
  [super tearDown];
}

#pragma mark - validateClaimMode return value

- (void)testReturnsTrueWhenConfiguredModeIsInSupportedSet {
  NSArray* supported = @[@"legacy", @"server_jwt"];
  BOOL ok = [TeakRemoteConfiguration validateClaimMode:@"server_jwt" againstSupported:supported];
  XCTAssertTrue(ok);
}

- (void)testReturnsTrueWhenLegacyDefaultIsSupported {
  NSArray* supported = @[@"legacy"];
  BOOL ok = [TeakRemoteConfiguration validateClaimMode:@"legacy" againstSupported:supported];
  XCTAssertTrue(ok);
}

- (void)testReturnsFalseWhenConfiguredModeNotSupported {
  NSArray* supported = @[@"legacy"];
  BOOL ok = [TeakRemoteConfiguration validateClaimMode:@"server_jwt" againstSupported:supported];
  XCTAssertFalse(ok);
}

#pragma mark - validateClaimMode log emission

- (void)testEmitsWarningLevelEventWhenModeUnsupported {
  __block NSString* observedEvent = nil;
  __block NSString* observedLevel = nil;
  __block NSDictionary* observedData = nil;
  stubProperty(self.teakMock, logListener,
               ^(NSString* _Nonnull event,
                 NSString* _Nonnull level,
                 NSDictionary* _Nullable eventData) {
                 if ([event isEqualToString:@"claim_mode.unsupported"]) {
                   observedEvent = event;
                   observedLevel = level;
                   observedData = eventData[@"event_data"];
                 }
               });

  NSArray* supported = @[@"legacy"];
  [TeakRemoteConfiguration validateClaimMode:@"server_jwt" againstSupported:supported];

  // Field shape mirrors Android's claim_mode.unsupported event so cross-SDK
  // log ingestion doesn't need per-platform branches.
  assertThat(observedEvent, is(@"claim_mode.unsupported"));
  assertThat(observedLevel, is(@"WARN"));
  assertThat(observedData[@"configured_claim_mode"], is(@"server_jwt"));
  assertThat(observedData[@"supported_claim_modes"], is(@"[\"legacy\"]"));
}

- (void)testDoesNotEmitWarningWhenModeIsSupported {
  __block BOOL warningSeen = NO;
  stubProperty(self.teakMock, logListener,
               ^(NSString* _Nonnull event,
                 NSString* _Nonnull level,
                 NSDictionary* _Nullable eventData) {
                 if ([event isEqualToString:@"claim_mode.unsupported"]) {
                   warningSeen = YES;
                 }
               });

  NSArray* supported = @[@"legacy", @"server_jwt"];
  [TeakRemoteConfiguration validateClaimMode:@"legacy" againstSupported:supported];

  XCTAssertFalse(warningSeen, @"warning must not fire when configured mode is supported");
}

#pragma mark - Defensive handling of unexpected server payloads

- (void)testReturnsTrueAndDoesNotWarnWhenSupportedListMissing {
  __block BOOL warningSeen = NO;
  stubProperty(self.teakMock, logListener,
               ^(NSString* _Nonnull event,
                 NSString* _Nonnull level,
                 NSDictionary* _Nullable eventData) {
                 if ([event isEqualToString:@"claim_mode.unsupported"]) {
                   warningSeen = YES;
                 }
               });

  BOOL ok = [TeakRemoteConfiguration validateClaimMode:@"server_jwt" againstSupported:nil];
  XCTAssertTrue(ok);
  XCTAssertFalse(warningSeen, @"do not warn if server omitted supported_claim_modes");
}

- (void)testReturnsTrueWhenSupportedListIsNotAnArray {
  BOOL ok = [TeakRemoteConfiguration validateClaimMode:@"server_jwt" againstSupported:@"server_jwt"];
  XCTAssertTrue(ok);
}

@end
