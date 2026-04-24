#import <XCTest/XCTest.h>

#import "TeakRequest.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Re-expose the internal parse helper so tests can exercise it without
// driving a full NSURLSession round-trip. See CLAUDE.md "Header imports in tests".
@interface TeakRequest (ResponseParsingTests)
+ (NSDictionary* _Nonnull)parseJSONResponseData:(NSData* _Nullable)data
                                          error:(NSError* _Nullable* _Nullable)outError;
@end

@interface TeakRequestResponseParsingTests : XCTestCase
@end

@implementation TeakRequestResponseParsingTests

#pragma mark - Nil / empty data (error out-param left unchanged)

- (void)testReturnsEmptyDictForNilData {
  NSError* err = nil;
  NSDictionary* result = [TeakRequest parseJSONResponseData:nil error:&err];
  XCTAssertNotNil(result);
  XCTAssertEqualObjects(result, @{});
  XCTAssertNil(err);
}

- (void)testReturnsEmptyDictForZeroLengthData {
  NSError* err = nil;
  NSDictionary* result = [TeakRequest parseJSONResponseData:[NSData data] error:&err];
  XCTAssertNotNil(result);
  XCTAssertEqualObjects(result, @{});
  XCTAssertNil(err);
}

#pragma mark - Non-JSON bodies (e.g. HTML error page from a 500) — error populated

- (void)testReturnsEmptyDictForHTMLErrorBody {
  NSError* err = nil;
  NSData* html = [@"<html><body>500 Internal Server Error</body></html>" dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary* result = [TeakRequest parseJSONResponseData:html error:&err];
  XCTAssertEqualObjects(result, @{});
  XCTAssertNotNil(err);
}

- (void)testReturnsEmptyDictForGarbageBytes {
  NSError* err = nil;
  unsigned char bytes[] = {0xff, 0xfe, 0x00, 0x01};
  NSData* garbage = [NSData dataWithBytes:bytes length:sizeof(bytes)];
  NSDictionary* result = [TeakRequest parseJSONResponseData:garbage error:&err];
  XCTAssertEqualObjects(result, @{});
  XCTAssertNotNil(err);
}

#pragma mark - Valid JSON that is not an object — error populated

- (void)testReturnsEmptyDictForJSONArray {
  NSError* err = nil;
  NSData* jsonArray = [@"[1, 2, 3]" dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary* result = [TeakRequest parseJSONResponseData:jsonArray error:&err];
  XCTAssertEqualObjects(result, @{});
  XCTAssertNotNil(err);
}

- (void)testReturnsEmptyDictForJSONString {
  NSError* err = nil;
  NSData* jsonString = [@"\"just a string\"" dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary* result = [TeakRequest parseJSONResponseData:jsonString error:&err];
  XCTAssertEqualObjects(result, @{});
  XCTAssertNotNil(err);
}

#pragma mark - Valid JSON objects — error left unchanged

- (void)testReturnsParsedDictForValidJSONObject {
  NSError* err = nil;
  NSData* jsonData = [@"{\"status\":\"ok\",\"id\":42}" dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary* result = [TeakRequest parseJSONResponseData:jsonData error:&err];
  XCTAssertEqualObjects(result[@"status"], @"ok");
  XCTAssertEqualObjects(result[@"id"], @42);
  XCTAssertNil(err);
}

- (void)testReturnsEmptyDictForEmptyJSONObject {
  NSError* err = nil;
  NSData* jsonData = [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary* result = [TeakRequest parseJSONResponseData:jsonData error:&err];
  XCTAssertEqualObjects(result, @{});
  XCTAssertNil(err);
}

#pragma mark - nil outError pointer is tolerated

- (void)testAcceptsNilOutErrorPointer {
  NSData* garbage = [@"not json" dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary* result = [TeakRequest parseJSONResponseData:garbage error:NULL];
  XCTAssertEqualObjects(result, @{});
}

@end
