#import <Foundation/Foundation.h>

/// Remembers the last live activity token forwarded for each activity id so repeat emissions of the
/// same token are not sent to the server again. In-memory only; cleared when the user changes.
@interface TeakLiveActivityTokenCache : NSObject

+ (nonnull TeakLiveActivityTokenCache*)sharedCache;

/// Returns YES, and records `signature` as the last one sent for `activityId`, if it differs from what
/// was last recorded. Returns NO if it matches, meaning the forward should be skipped. The claim is
/// recorded before the request is sent, so concurrent duplicates collapse as well.
///
/// On YES, `generation` receives the value to hand back to -releaseActivityId:signature:generation:.
- (BOOL)claimActivityId:(nonnull NSString*)activityId signature:(nonnull NSString*)signature generation:(nonnull NSUInteger*)generation;

/// Forgets a claim whose request failed, so the next emission is sent again. Does nothing if the cache
/// was reset or a different signature was claimed for `activityId` since.
- (void)releaseActivityId:(nonnull NSString*)activityId signature:(nonnull NSString*)signature generation:(NSUInteger)generation;

/// Forgets everything. Replies still in flight from before the reset can no longer release anything.
- (void)reset;

@end
