#import "TeakLiveActivityTokenCache.h"
#import "TeakOperation.h"

@interface TeakLiveActivityTokenCacheEntry : NSObject
@property (nonatomic, copy) NSString* signature;
@property (nonatomic, strong) TeakOperation* operation;
@end

@implementation TeakLiveActivityTokenCacheEntry
@end

@interface TeakLiveActivityTokenCache ()
@property (nonatomic, strong) NSMutableDictionary<NSString*, TeakLiveActivityTokenCacheEntry*>* entries;
@end

// Leaf lock: the only thing called while it is held is -isCancelled, which does not take this lock.
@implementation TeakLiveActivityTokenCache

+ (nonnull TeakLiveActivityTokenCache*)sharedCache {
  static TeakLiveActivityTokenCache* cache = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    cache = [[TeakLiveActivityTokenCache alloc] init];
  });
  return cache;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _entries = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (nullable TeakOperation*)operationForActivityId:(nonnull NSString*)activityId signature:(nonnull NSString*)signature orRecord:(nonnull TeakOperation*)op {
  @synchronized(self) {
    TeakLiveActivityTokenCacheEntry* entry = self.entries[activityId];
    if (entry != nil && [entry.signature isEqualToString:signature] && !entry.operation.isCancelled) {
      return entry.operation;
    }

    entry = [[TeakLiveActivityTokenCacheEntry alloc] init];
    entry.signature = signature;
    entry.operation = op;
    self.entries[activityId] = entry;
    return nil;
  }
}

- (void)releaseOperation:(nonnull TeakOperation*)op forActivityId:(nonnull NSString*)activityId {
  @synchronized(self) {
    if (self.entries[activityId].operation == op) {
      [self.entries removeObjectForKey:activityId];
    }
  }
}

- (void)reset {
  @synchronized(self) {
    [self.entries removeAllObjects];
  }
}

@end
