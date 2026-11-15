#import <XCTest/XCTest.h>

#import "TeakRequest.h"
#import <Teak/Teak.h>

#include <sys/errno.h>

@import OCHamcrest;
@import OCMockito;

// Re-expose the internal predicates and stop-policy constant so tests can
// exercise them without driving a full NSURLSession round-trip. See
// CLAUDE.md "Header imports in tests".
extern const NSUInteger TeakRequestMaxSocketRetries;

@interface TeakRequest (SocketErrorTests)
+ (BOOL)isRetryableSocketError:(NSError* _Nullable)error;
+ (BOOL)shouldRetryResponse:(NSHTTPURLResponse* _Nullable)response error:(NSError* _Nullable)error retryCount:(NSUInteger)retryCount;
@end

@interface TeakRequestSocketErrorTests : XCTestCase
@end

@implementation TeakRequestSocketErrorTests

#pragma mark - nil

- (void)testNilErrorIsNotRetryable {
  XCTAssertFalse([TeakRequest isRetryableSocketError:nil]);
}

#pragma mark - The verified production shape: top-level NSPOSIXErrorDomain/ECONNABORTED

// This is the exact error TeakLog's analogous retry was built from
// production telemetry to handle, and matches Apple's own documented
// "NSURLSessionTask receives error 53 when app is relaunched from
// background" failure mode.
- (void)testTopLevelPOSIXConnectionAbortedIsRetryable {
  NSError* error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ECONNABORTED userInfo:nil];
  XCTAssertTrue([TeakRequest isRetryableSocketError:error]);
}

- (void)testTopLevelPOSIXOtherCodeIsNotRetryable {
  NSError* error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOTCONN userInfo:nil];
  XCTAssertFalse([TeakRequest isRetryableSocketError:error]);
}

#pragma mark - Boundary: a same-shaped error in a different domain does not match

- (void)testSameCodeInDifferentDomainIsNotRetryable {
  NSError* error = [NSError errorWithDomain:NSURLErrorDomain code:ECONNABORTED userInfo:nil];
  XCTAssertFalse([TeakRequest isRetryableSocketError:error]);
}

// NSURLErrorNetworkConnectionLost is a distinct failure (connection severed
// mid-load, often server-side) with its own nested CFNetwork stream codes —
// not the OS-background-socket case this predicate targets.
- (void)testNetworkConnectionLostIsNotRetryable {
  NSError* error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNetworkConnectionLost userInfo:nil];
  XCTAssertFalse([TeakRequest isRetryableSocketError:error]);
}

#pragma mark - Nested under NSUnderlyingErrorKey

- (void)testNestedUnderlyingPOSIXConnectionAbortedIsRetryable {
  NSError* underlying = [NSError errorWithDomain:NSPOSIXErrorDomain code:ECONNABORTED userInfo:nil];
  NSError* error = [NSError errorWithDomain:NSURLErrorDomain
                                        code:NSURLErrorUnknown
                                    userInfo:@{NSUnderlyingErrorKey : underlying}];
  XCTAssertTrue([TeakRequest isRetryableSocketError:error]);
}

- (void)testNestedUnderlyingPOSIXOtherCodeIsNotRetryable {
  NSError* underlying = [NSError errorWithDomain:NSPOSIXErrorDomain code:ENOTCONN userInfo:nil];
  NSError* error = [NSError errorWithDomain:NSURLErrorDomain
                                        code:NSURLErrorUnknown
                                    userInfo:@{NSUnderlyingErrorKey : underlying}];
  XCTAssertFalse([TeakRequest isRetryableSocketError:error]);
}

@end

///// The retry gate: response:payload:withError: calls
///// +shouldRetryResponse:error:retryCount: to decide whether to fire another
///// retry. These pin what counts as a retryable failure and the count boundary,
///// so the gate can't loop past the stop policy or silently stop retrying a
///// fresh no-response failure.

@interface TeakRequestRetryGateTests : XCTestCase
@end

@implementation TeakRequestRetryGateTests

- (NSError*)socketError {
  return [NSError errorWithDomain:NSPOSIXErrorDomain code:ECONNABORTED userInfo:nil];
}

- (NSError*)urlError:(NSInteger)code {
  return [NSError errorWithDomain:NSURLErrorDomain code:code userInfo:nil];
}

- (void)testRetriesASocketErrorBelowTheLimit {
  XCTAssertTrue([TeakRequest shouldRetryResponse:nil error:[self socketError] retryCount:TeakRequestMaxSocketRetries - 1]);
}

- (void)testRetriesAnyNoResponseFailureBelowTheLimit {
  XCTAssertTrue([TeakRequest shouldRetryResponse:nil error:[self urlError:NSURLErrorNetworkConnectionLost] retryCount:TeakRequestMaxSocketRetries - 1]);
  XCTAssertTrue([TeakRequest shouldRetryResponse:nil error:[self urlError:NSURLErrorTimedOut] retryCount:TeakRequestMaxSocketRetries - 1]);
}

- (void)testDoesNotRetryAtTheLimit {
  XCTAssertFalse([TeakRequest shouldRetryResponse:nil error:[self socketError] retryCount:TeakRequestMaxSocketRetries]);
  XCTAssertFalse([TeakRequest shouldRetryResponse:nil error:[self urlError:NSURLErrorTimedOut] retryCount:TeakRequestMaxSocketRetries]);
}

- (void)testDoesNotRetryPastTheLimit {
  XCTAssertFalse([TeakRequest shouldRetryResponse:nil error:[self socketError] retryCount:TeakRequestMaxSocketRetries + 1]);
}

- (void)testDoesNotRetryACancellation {
  XCTAssertFalse([TeakRequest shouldRetryResponse:nil error:[self urlError:NSURLErrorCancelled] retryCount:0]);
}

// A reply with a status is an answer, not a transport failure.
- (void)testDoesNotRetryAnHttpReply {
  NSHTTPURLResponse* response = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"https://gocarrot.com"]
                                                            statusCode:503
                                                           HTTPVersion:@"HTTP/1.1"
                                                          headerFields:@{}];
  XCTAssertFalse([TeakRequest shouldRetryResponse:response error:nil retryCount:0]);
}

@end
