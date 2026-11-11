#import <Foundation/Foundation.h>

@class TeakOperation;

/// Remembers the request operation behind the last live activity token forwarded for each activity id,
/// so a repeat emission of the same token gets that operation back instead of sending again.
/// In-memory only; cleared when the user changes.
@interface TeakLiveActivityTokenCache : NSObject

+ (nonnull TeakLiveActivityTokenCache*)sharedCache;

/// Returns the operation already recorded for `activityId` if it was recorded with the same
/// `signature` and has not been cancelled. Otherwise records `op` in its place and returns nil, meaning
/// the caller should send `op`. Check and record are one step, so concurrent duplicates collapse.
- (nullable TeakOperation*)operationForActivityId:(nonnull NSString*)activityId signature:(nonnull NSString*)signature orRecord:(nonnull TeakOperation*)op;

/// Forgets `op` after its request failed, so the next emission is sent again. Does nothing if `op`
/// is no longer what is recorded for `activityId`: it was superseded, or the cache was reset.
- (void)releaseOperation:(nonnull TeakOperation*)op forActivityId:(nonnull NSString*)activityId;

/// Forgets everything. Replies still in flight from before the reset can no longer release anything.
- (void)reset;

@end
