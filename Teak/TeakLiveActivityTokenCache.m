#import "TeakLiveActivityTokenCache.h"

@interface TeakLiveActivityTokenCache ()
@property (nonatomic, strong) NSMutableDictionary<NSString*, NSString*>* signatures;
@property (nonatomic) NSUInteger generation;
@end

// Leaf lock: nothing is called while it is held, so it is safe to take under any other lock.
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
    _signatures = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (BOOL)claimActivityId:(nonnull NSString*)activityId signature:(nonnull NSString*)signature generation:(nonnull NSUInteger*)generation {
  @synchronized(self) {
    if ([self.signatures[activityId] isEqualToString:signature]) {
      return NO;
    }
    self.signatures[activityId] = [signature copy];
    *generation = self.generation;
    return YES;
  }
}

- (void)releaseActivityId:(nonnull NSString*)activityId signature:(nonnull NSString*)signature generation:(NSUInteger)generation {
  @synchronized(self) {
    if (generation == self.generation && [self.signatures[activityId] isEqualToString:signature]) {
      [self.signatures removeObjectForKey:activityId];
    }
  }
}

- (void)reset {
  @synchronized(self) {
    [self.signatures removeAllObjects];
    self.generation++;
  }
}

@end
