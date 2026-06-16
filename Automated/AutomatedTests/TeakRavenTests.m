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
@end

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

@end
