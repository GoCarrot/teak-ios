#import <XCTest/XCTest.h>

#import "TeakAppConfiguration.h"
#import "TeakConfiguration.h"
#import "TeakDeviceConfiguration.h"
#import "TeakLog.h"
#import "TeakRaven.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Re-expose internal Teak properties needed to build a TeakRaven
@interface Teak ()
@property (strong, nonatomic) TeakConfiguration* _Nonnull configuration;
@property (strong, nonatomic) TeakLog* _Nonnull log;
@property (strong, nonatomic) TeakRaven* _Nonnull sdkRaven;
@property (strong, nonatomic, readwrite) NSString* _Nonnull sdkVersion;
- (void)reportTestException;
@end

// The shared instance is a plain global with external linkage, so a test can
// install a real Teak to exercise the singleton-routed exception path.
extern Teak* _Nullable _teakSharedInstance;

// Re-expose payloadTemplate for inspection
@interface TeakRaven ()
@property (strong, nonatomic) NSMutableDictionary* payloadTemplate;
@end

// Re-expose runId as read-write so tests can inject a known value
@interface TeakLog ()
@property (strong, nonatomic) NSString* runId;
@end

@interface TeakRavenTests : XCTestCase
@property (strong, nonatomic) TeakLog* log;
@property (strong, nonatomic) Teak* teakMock;
@end

@implementation TeakRavenTests

- (void)setUp {
  TeakDeviceConfiguration* deviceConfig = mock([TeakDeviceConfiguration class]);
  [given([deviceConfig deviceId]) willReturn:@"test-device-id"];

  TeakAppConfiguration* appConfig = mock([TeakAppConfiguration class]);
  [given([appConfig appId]) willReturn:@"test-app-id"];
  [given([appConfig appVersion]) willReturn:@"1"];
  [given([appConfig appVersionName]) willReturn:@"1.0.0"];
  [given([appConfig isProduction]) willReturn:@NO];

  TeakConfiguration* config = mock([TeakConfiguration class]);
  [given([config deviceConfiguration]) willReturn:deviceConfig];
  [given([config appConfiguration]) willReturn:appConfig];

  self.teakMock = mock([Teak class]);
  [given([self.teakMock sdkVersion]) willReturn:@"4.3.13-test"];
  [given([self.teakMock configuration]) willReturn:config];

  self.log = [[TeakLog alloc] initForTeak:self.teakMock withAppId:@"test"];
  [given([self.teakMock log]) willReturn:self.log];
}

- (void)testPayloadTemplateTagsContainRunId {
  NSString* knownRunId = @"deadbeefcafe0123456789abcdef0042";
  self.log.runId = knownRunId;

  TeakRaven* raven = [TeakRaven ravenForTeak:self.teakMock];

  assertThat(raven.payloadTemplate[@"tags"][@"run_id"], is(knownRunId));
}

- (void)testPayloadTemplateTagsOmitRunIdWhenLogIsNil {
  [given([self.teakMock log]) willReturn:nil];

  TeakRaven* raven = [TeakRaven ravenForTeak:self.teakMock];

  // nil log must degrade gracefully: tag absent, raven still created
  XCTAssertNotNil(raven);
  XCTAssertNil(raven.payloadTemplate[@"tags"][@"run_id"]);
}

// A caught exception (teak_catch_report → reportWithHelper) must surface an
// observable "exception" TeakLog event whose event_data matches Android's
// throwableToMap shape: type ← NSException.name, value ← NSException.reason.
// reportTestException is the exact path the C-739 cleanroom test drives.
- (void)testReportTestExceptionEmitsObservableExceptionEvent {
  Teak* teak = [[Teak alloc] init];
  teak.sdkVersion = @"4.3.13-test";
  teak.log = [[TeakLog alloc] initForTeak:teak withAppId:@"test"];

  __block NSString* capturedEventType = nil;
  __block NSDictionary* capturedEventData = nil;
  teak.logListener = ^(NSString* event, NSString* level, NSDictionary* payload) {
    if ([event isEqualToString:@"exception"]) {
      capturedEventType = payload[@"event_type"];
      capturedEventData = payload[@"event_data"];
    }
  };

  // Raven built from the fully-stubbed mock so payloadTemplate construction
  // doesn't bail; its endpoint stays nil so nothing hits the network.
  teak.sdkRaven = [TeakRaven ravenForTeak:self.teakMock];

  Teak* previousShared = _teakSharedInstance;
  _teakSharedInstance = teak;
  @try {
    [teak reportTestException];
  } @finally {
    _teakSharedInstance = previousShared;
  }

  assertThat(capturedEventType, is(@"exception"));
  assertThat(capturedEventData[@"type"], is(@"ReportTestException"));
  assertThat(capturedEventData[@"value"], is(@"Version: 4.3.13-test"));
}

- (void)testExceptionLogEventDataMapsNameToTypeAndReasonToValue {
  NSException* exception = [NSException exceptionWithName:@"ReportTestException"
                                                  reason:@"Version: 4.3.13"
                                                userInfo:nil];

  NSDictionary* eventData = [TeakRaven exceptionLogEventDataForException:exception];

  assertThat(eventData[@"type"], is(@"ReportTestException"));
  assertThat(eventData[@"value"], is(@"Version: 4.3.13"));
}

- (void)testExceptionLogEventDataIsNilSafeForMissingReason {
  NSException* exception = [NSException exceptionWithName:@"NoReason" reason:nil userInfo:nil];

  NSDictionary* eventData = [TeakRaven exceptionLogEventDataForException:exception];

  // A nil reason is omitted rather than crashing the dictionary build.
  assertThat(eventData[@"type"], is(@"NoReason"));
  XCTAssertNil(eventData[@"value"]);
}

@end
