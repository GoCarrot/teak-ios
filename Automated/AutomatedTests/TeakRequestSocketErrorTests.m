#import <XCTest/XCTest.h>

#import "TeakRequest+Internal.h"
#import <Teak/Teak.h>

#include <sys/errno.h>

@import OCHamcrest;
@import OCMockito;

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
///// +shouldRetrySocketError:retryCount: to decide whether to fire another
///// retry. These pin the count boundary so the gate can't loop past the stop
///// policy or silently stop retrying a fresh socket error.

@interface TeakRequestRetryGateTests : XCTestCase
@end

@implementation TeakRequestRetryGateTests

- (void)testRetriesASocketErrorBelowTheLimit {
  NSError* error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ECONNABORTED userInfo:nil];
  XCTAssertTrue([TeakRequest shouldRetrySocketError:error retryCount:TeakRequestMaxSocketRetries - 1]);
}

- (void)testDoesNotRetryASocketErrorAtTheLimit {
  NSError* error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ECONNABORTED userInfo:nil];
  XCTAssertFalse([TeakRequest shouldRetrySocketError:error retryCount:TeakRequestMaxSocketRetries]);
}

- (void)testDoesNotRetryASocketErrorPastTheLimit {
  NSError* error = [NSError errorWithDomain:NSPOSIXErrorDomain code:ECONNABORTED userInfo:nil];
  XCTAssertFalse([TeakRequest shouldRetrySocketError:error retryCount:TeakRequestMaxSocketRetries + 1]);
}

- (void)testDoesNotRetryANonSocketErrorBelowTheLimit {
  NSError* error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNetworkConnectionLost userInfo:nil];
  XCTAssertFalse([TeakRequest shouldRetrySocketError:error retryCount:TeakRequestMaxSocketRetries - 1]);
}

- (void)testDoesNotRetryANonSocketErrorAtTheLimit {
  NSError* error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNetworkConnectionLost userInfo:nil];
  XCTAssertFalse([TeakRequest shouldRetrySocketError:error retryCount:TeakRequestMaxSocketRetries]);
}

@end
