#import "TeakSessionFixtures.h"

#import "TeakAppConfiguration.h"
#import "TeakDeviceConfiguration.h"
#import "TeakRemoteConfiguration.h"
#import "TeakSession.h"

@import OCMockito;

@implementation TeakSessionFixtures

+ (TeakSession*)mockSessionWithEndpointConfigurations:(NSDictionary*)endpointConfigurations {
  return [self mockSessionWithEndpointConfigurations:endpointConfigurations requestTimeoutInterval:60.0];
}

+ (TeakSession*)mockSessionWithEndpointConfigurations:(NSDictionary*)endpointConfigurations requestTimeoutInterval:(NSTimeInterval)requestTimeoutInterval {
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
  [given([remoteConfig endpointConfigurations]) willReturn:endpointConfigurations];
  [given([remoteConfig dynamicParameters]) willReturn:@{}];
  [given([remoteConfig requestTimeoutInterval]) willReturnDouble:requestTimeoutInterval];

  TeakSession* session = mock([TeakSession class]);
  [given([session appConfiguration]) willReturn:appConfig];
  [given([session deviceConfiguration]) willReturn:deviceConfig];
  [given([session remoteConfiguration]) willReturn:remoteConfig];
  [given([session sessionId]) willReturn:@"test-session"];
  [given([session userId]) willReturn:nil];
  return session;
}

@end
