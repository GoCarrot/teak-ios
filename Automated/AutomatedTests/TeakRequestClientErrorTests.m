#import <XCTest/XCTest.h>

#import "TeakRequest+Internal.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

@interface TeakRequestClientErrorTests : XCTestCase
@end

@implementation TeakRequestClientErrorTests

- (void)testReturnsTitleFromDictWhenPresent {
  NSDictionary* err = @{@"title" : @"Bad API Key", @"message" : @"Invalid key"};
  XCTAssertEqualObjects([TeakRequest titleForClientError:err], @"Bad API Key");
}

- (void)testFallsBackToConfigurationErrorWhenTitleMissing {
  NSDictionary* err = @{@"message" : @"Something went wrong"};
  XCTAssertEqualObjects([TeakRequest titleForClientError:err], @"Configuration Error");
}

- (void)testFallsBackToConfigurationErrorForNilDict {
  XCTAssertEqualObjects([TeakRequest titleForClientError:nil], @"Configuration Error");
}

- (void)testFallsBackToConfigurationErrorForEmptyDict {
  XCTAssertEqualObjects([TeakRequest titleForClientError:@{}], @"Configuration Error");
}

- (void)testFallsBackToConfigurationErrorWhenTitleIsNSNull {
  NSDictionary* err = @{@"title" : [NSNull null]};
  XCTAssertEqualObjects([TeakRequest titleForClientError:err], @"Configuration Error");
}

@end
