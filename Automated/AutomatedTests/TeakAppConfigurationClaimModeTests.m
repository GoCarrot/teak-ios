#import <XCTest/XCTest.h>

#import "TeakAppConfiguration.h"

@interface TeakAppConfigurationClaimModeTests : XCTestCase
@end

@implementation TeakAppConfigurationClaimModeTests

- (void)testClaimModeDefaultsToLegacyWhenInfoPlistKeyAbsent {
  // The test bundle's Info.plist does not declare TeakClaimMode, so a real
  // TeakAppConfiguration constructed against [NSBundle mainBundle] should
  // fall back to the documented default of @"legacy".
  TeakAppConfiguration* config = [[TeakAppConfiguration alloc] initWithAppId:@"app-id" apiKey:@"api-key"];

  XCTAssertNotNil(config.claimMode, @"claimMode must always be populated");
  XCTAssertEqualObjects(config.claimMode, @"legacy",
                        @"Apps without TeakClaimMode in Info.plist must default to 'legacy'");
}

- (void)testClaimModeIsExposedInToHForLogging {
  TeakAppConfiguration* config = [[TeakAppConfiguration alloc] initWithAppId:@"app-id" apiKey:@"api-key"];
  NSDictionary* dict = [config to_h];

  XCTAssertNotNil(dict[@"claimMode"], @"to_h must include claimMode for the configuration log event");
  XCTAssertEqualObjects(dict[@"claimMode"], config.claimMode);
}

@end
