#import <XCTest/XCTest.h>

#import "TeakRequest.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Re-expose the internal parse helper so tests can exercise it without
// driving a full NSURLSession round-trip. See CLAUDE.md "Header imports in tests".
@interface TeakRequest (ResponseParsingTests)
+ (NSDictionary* _Nonnull)parseJSONResponseData:(NSData* _Nullable)data;
@end

@interface TeakRequestResponseParsingTests : XCTestCase
@end

@implementation TeakRequestResponseParsingTests

#pragma mark - Nil / empty data

- (void)testReturnsEmptyDictForNilData {
  NSDictionary* result = [TeakRequest parseJSONResponseData:nil];
  XCTAssertNotNil(result);
  XCTAssertEqualObjects(result, @{});
}

- (void)testReturnsEmptyDictForZeroLengthData {
  NSDictionary* result = [TeakRequest parseJSONResponseData:[NSData data]];
  XCTAssertNotNil(result);
  XCTAssertEqualObjects(result, @{});
}

#pragma mark - Non-JSON bodies (e.g. HTML error page from a 500)

- (void)testReturnsEmptyDictForHTMLErrorBody {
  NSData* html = [@"<html><body>500 Internal Server Error</body></html>" dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary* result = [TeakRequest parseJSONResponseData:html];
  XCTAssertNotNil(result);
  XCTAssertEqualObjects(result, @{});
}

- (void)testReturnsEmptyDictForGarbageBytes {
  unsigned char bytes[] = {0xff, 0xfe, 0x00, 0x01};
  NSData* garbage = [NSData dataWithBytes:bytes length:sizeof(bytes)];
  NSDictionary* result = [TeakRequest parseJSONResponseData:garbage];
  XCTAssertNotNil(result);
  XCTAssertEqualObjects(result, @{});
}

#pragma mark - Valid JSON that is not an object

- (void)testReturnsEmptyDictForJSONArray {
  NSData* jsonArray = [@"[1, 2, 3]" dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary* result = [TeakRequest parseJSONResponseData:jsonArray];
  XCTAssertNotNil(result);
  XCTAssertEqualObjects(result, @{});
}

- (void)testReturnsEmptyDictForJSONString {
  NSData* jsonString = [@"\"just a string\"" dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary* result = [TeakRequest parseJSONResponseData:jsonString];
  XCTAssertNotNil(result);
  XCTAssertEqualObjects(result, @{});
}

#pragma mark - Valid JSON objects

- (void)testReturnsParsedDictForValidJSONObject {
  NSData* jsonData = [@"{\"status\":\"ok\",\"id\":42}" dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary* result = [TeakRequest parseJSONResponseData:jsonData];
  XCTAssertEqualObjects(result[@"status"], @"ok");
  XCTAssertEqualObjects(result[@"id"], @42);
}

- (void)testReturnsEmptyDictForEmptyJSONObject {
  NSData* jsonData = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary* result = [TeakRequest parseJSONResponseData:jsonData];
  XCTAssertEqualObjects(result, @{});
}

@end
