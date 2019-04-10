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

/////

- (void)testEmptyPayload {
  XCTAssertEqualObjects(TeakFormEncode(@"some_dict", self.payload, NO), @"");
}

- (void)testPayloadContainingOnlyNSNull {
  self.payload[@"value_is_null"] = [NSNull null];
  XCTAssertEqualObjects(TeakFormEncode(@"some_dict", self.payload, NO), @"");
}

- (void)testStringPayload {
  self.payload[@"value_is_string"] = @"a_string";
  XCTAssertEqualObjects(TeakFormEncode(@"some_dict", self.payload, NO), @"some_dict[value_is_string]=a_string");

  XCTAssertEqualObjects(TeakFormEncode(@"value_is_string", @"a_string", NO), @"value_is_string=a_string");
}

- (void)testStringPayloadWithSpacesInValue {
  self.payload[@"value_is_string"] = @"a string";
  XCTAssertEqualObjects(TeakFormEncode(@"some_dict", self.payload, NO), @"some_dict[value_is_string]=a string");

  XCTAssertEqualObjects(TeakFormEncode(@"value_is_string", @"a string", NO), @"value_is_string=a string");
}

- (void)testPerformanceExample {
  // This is an example of a performance test case.
  [self measureBlock:^{
      // Put the code you want to measure the time of here.
  }];
}

@end
