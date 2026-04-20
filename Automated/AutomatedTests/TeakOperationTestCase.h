#import <XCTest/XCTest.h>

#import "TeakOperation.h"

// Expose TeakOperation's private replyParser property for tests that want to exercise the
// reply-parsing block directly without actually dispatching a network request.
@interface TeakOperation ()
@property (nonatomic, copy, nullable) id (^replyParser)(NSDictionary* _Nonnull);
@end

/// XCTestCase base class with helpers shared across TeakOperation-exercising suites.
@interface TeakOperationTestCase : XCTestCase

/// Run a TeakOperation to completion on a throwaway queue and return its result.
/// Suitable for operations constructed via +withResult: (no real network activity).
- (nullable TeakOperationResult*)runOperationAndGetResult:(nonnull TeakOperation*)op;

/// Extract the {endpoint, payload} dictionary stashed on the operation's NSInvocation.
/// Lets tests verify request construction without invoking the network path.
- (nonnull NSDictionary*)requestParamsFromOperation:(nonnull TeakOperation*)op;

@end
