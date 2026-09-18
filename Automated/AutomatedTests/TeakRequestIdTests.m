#import <XCTest/XCTest.h>

#import "TeakAppConfiguration.h"
#import "TeakDeviceConfiguration.h"
#import "TeakRemoteConfiguration.h"
#import "TeakRequest.h"
#import "TeakSession.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Re-declared: internal to the SDK.
extern NSDictionary* TeakVersionDict;

@interface TeakRequest (RequestIdTests)
@end

@interface TeakRequestIdTests : XCTestCase
@end

@implementation TeakRequestIdTests

- (void)setUp {
  TeakVersionDict = @{@"sdk_version" : @"4.3.13-test"};
}

- (TeakSession*)makeMockSession {
  TeakAppConfiguration* appConfig = mock([TeakAppConfiguration class]);
  [given([appConfig appId]) willReturn:@"test-app-id"];
  [given([appConfig appVersion]) willReturn:@"1"];
  [given([appConfig appVersionName]) willReturn:@"1.0.0"];
  [given([appConfig bundleId]) willReturn:@"io.teak.test"];
  [given([appConfig isProduction]) willReturn:@NO];

  TeakDeviceConfiguration* deviceConfig = mock([TeakDeviceConfiguration class]);
  [given([deviceConfig platformString]) willReturn:@"iOS"];
  [given([deviceConfig deviceModel]) willReturn:@"iPhone-test"];
  [given([deviceConfig deviceId]) willReturn:@"test-device-id"];

  TeakRemoteConfiguration* remoteConfig = mock([TeakRemoteConfiguration class]);
  [given([remoteConfig endpointConfigurations]) willReturn:@{}];
  [given([remoteConfig dynamicParameters]) willReturn:@{}];

  TeakSession* session = mock([TeakSession class]);
  [given([session appConfiguration]) willReturn:appConfig];
  [given([session deviceConfiguration]) willReturn:deviceConfig];
  [given([session remoteConfiguration]) willReturn:remoteConfig];
  [given([session userId]) willReturn:nil];
  return session;
}

- (TeakRequest*)requestForEndpoint:(NSString*)endpoint {
  return [TeakRequest requestWithSession:[self makeMockSession]
                             forEndpoint:endpoint
                             withPayload:@{}
                                  method:@"POST"
                                callback:nil];
}

- (void)testLiveActivityEndpointsCarryRequestId {
  for (NSString* endpoint in @[ @"/me/live_activities", @"/me/live_activity_updates", @"/me/cancel_all_live_activity_updates" ]) {
    TeakRequest* request = [self requestForEndpoint:endpoint];
    XCTAssertNotNil(request, @"%@", endpoint);
    XCTAssertNotNil(request.requestId, @"%@", endpoint);
    XCTAssertEqualObjects(request.payload[@"request_id"], request.requestId, @"%@", endpoint);
  }
}

- (void)testRequestIdIsUniquePerRequest {
  TeakRequest* a = [self requestForEndpoint:@"/me/live_activities"];
  TeakRequest* b = [self requestForEndpoint:@"/me/live_activities"];
  XCTAssertNotEqualObjects(a.payload[@"request_id"], b.payload[@"request_id"]);
}

- (void)testOtherEndpointsDoNotCarryRequestId {
  TeakRequest* request = [self requestForEndpoint:@"/me/channel_state"];
  XCTAssertNotNil(request);
  XCTAssertNil(request.payload[@"request_id"]);
}

@end
