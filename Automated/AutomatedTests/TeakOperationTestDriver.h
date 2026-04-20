#import <Foundation/Foundation.h>

#import "TeakOperation.h"

// Expose TeakOperation's private replyParser property for tests that want to exercise the
// reply-parsing block directly without actually dispatching a network request.
@interface TeakOperation ()
@property (nonatomic, copy, nullable) id (^replyParser)(NSDictionary* _Nonnull);
@end

/// Helper object for exercising TeakOperations in unit tests. Held by each test as a
/// property (created in -setUp) so additional test helpers can compose alongside it as
/// independent properties without collapsing into a shared base class.
@interface TeakOperationTestDriver : NSObject

/// Run a TeakOperation to completion on a throwaway queue and return its result.
/// Suitable for operations constructed via +withResult: (no real network activity).
- (nullable TeakOperationResult*)runSync:(nonnull TeakOperation*)op;

/// Extract the {endpoint, payload} dictionary stashed on the operation's NSInvocation.
/// Lets tests verify request construction without invoking the network path.
- (nonnull NSDictionary*)requestParamsFor:(nonnull TeakOperation*)op;

@end
