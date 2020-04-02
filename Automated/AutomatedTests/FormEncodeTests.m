#import <XCTest/XCTest.h>

extern NSString* TeakFormEncode(NSString* name, id value, BOOL escape);

@interface FormEncodeTests : XCTestCase
@property (nonatomic) NSMutableDictionary* payload;
@end

@implementation FormEncodeTests

- (void)setUp {
  // Put setup code here. This method is called before the invocation of each test method in the class.
  self.payload = [[NSMutableDictionary alloc] init];
}

- (void)tearDown {
  // Put teardown code here. This method is called after the invocation of each test method in the class.
}

- (void)testEmptyPayload {
  XCTAssertEqualObjects(TeakFormEncode(@"some_dict", self.payload, YES), @"");
}

- (void)testPayloadContainingOnlyNSNull {
  self.payload[@"value_is_null"] = [NSNull null];
  XCTAssertEqualObjects(TeakFormEncode(@"some_dict", self.payload, YES), @"");
}

- (void)testStringPayload {
  self.payload[@"value_is_string"] = @"a_string";
  XCTAssertEqualObjects(TeakFormEncode(@"some_dict", self.payload, YES), @"some_dict[value_is_string]=a_string");

  XCTAssertEqualObjects(TeakFormEncode(@"value_is_string", @"a_string", YES), @"value_is_string=a_string");
}

- (void)testStringPayloadWithSpacesInValue {
  self.payload[@"value_is_string"] = @"a string";
  XCTAssertEqualObjects(TeakFormEncode(@"some_dict", self.payload, YES), @"some_dict[value_is_string]=a%20string");

  XCTAssertEqualObjects(TeakFormEncode(@"value_is_string", @"a string", YES), @"value_is_string=a%20string");
}

- (void)testStringPayloadWithPercentSignsInValue {
  self.payload[@"value_is_string"] = @"string_has_%_in_it";
  XCTAssertEqualObjects(TeakFormEncode(@"some_dict", self.payload, YES), @"some_dict[value_is_string]=string_has_%25_in_it");

  XCTAssertEqualObjects(TeakFormEncode(@"value_is_string", @"string_has_%_in_it", YES), @"value_is_string=string_has_%25_in_it");
}

- (void)testStringPayloadWithPlusSignInValue {
  XCTAssertEqualObjects(TeakFormEncode(@"sig", @"am+j\\/WDcNGyMsrROfN4N3EizCF5IQ2z7YwGyjTpItPs=", YES), @"sig=am%2Bj\\%2FWDcNGyMsrROfN4N3EizCF5IQ2z7YwGyjTpItPs%3D");
}

- (void)testPerformanceExample {
  // This is an example of a performance test case.
  [self measureBlock:^{
      // Put the code you want to measure the time of here.
  }];
}

@end
