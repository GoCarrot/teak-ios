#import <XCTest/XCTest.h>

#import "TeakRequest.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Re-expose the internal helper so tests can exercise it without
// driving a full request lifecycle. See CLAUDE.md "Header imports in tests".
@interface TeakRequest (ClientErrorTests)
+ (NSString* _Nonnull)titleForClientError:(NSDictionary* _Nullable)clientError;
@end

@interface TeakRequestClientErrorTests : XCTestCase
@end

@implementation TeakRequestClientErrorTests

- (void)testReturnsTitleFromDictWhenPresent {
  NSDictionary* err = @{@"title" : @"Bad API Key", @"message" : @"Invalid key"};
  XCTAssertEqualObjects([TeakRequest titleForClientError:err], @"Bad API Key");
}

- (void)testFallsBackToConfigurationErrorWhenTitleMissing {
  NSDictionary* err = @{@"message" : @"Something went wrong"};
  XCTAssertEqualObjects([TeakRequest titleForClientError:err], @"Configuration Error",
                        @"Title must fall back to 'Configuration Error' when the key is missing — "
                        @"the original ternary was inverted and returned nil here, crashing "
                        @"TeakIntegrationChecker.reportError:forCategory:");
}

- (void)testFallsBackToConfigurationErrorForNilDict {
  XCTAssertEqualObjects([TeakRequest titleForClientError:nil], @"Configuration Error");
}

- (void)testFallsBackToConfigurationErrorForEmptyDict {
  XCTAssertEqualObjects([TeakRequest titleForClientError:@{}], @"Configuration Error");
}

- (void)testFallsBackToConfigurationErrorWhenTitleIsNSNull {
  NSDictionary* err = @{@"title" : [NSNull null]};
  XCTAssertEqualObjects([TeakRequest titleForClientError:err], @"Configuration Error",
                        @"NSNull must be treated the same as a missing key — it cannot be used as "
                        @"a dictionary key by the downstream integration checker.");
}

@end
