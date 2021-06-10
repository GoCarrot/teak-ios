#import "TeakWaitForDeepLink.h"

@interface TeakWaitForDeepLink ()
@property (nonatomic, readwrite) BOOL hasBeenAdded;
@property (strong, nonatomic) NSOperation* operation;
@end

@implementation TeakWaitForDeepLink

- (id)init {
  self = [super init];
  if (self) {
    self.hasBeenAdded = NO;
    self.operation = [NSBlockOperation blockOperationWithBlock:^{}];
  }
  return self;
}

- (BOOL)addToQueue:(nonnull NSOperationQueue*)queue {
  @synchronized(self.operation) {
    if (!self.hasBeenAdded) {
      self.hasBeenAdded = YES;
      [queue addOperation:self.operation];
      return YES;
    }
  }
  return NO;
}

- (void)addAsDependency:(nonnull NSOperation*)operation {
  [operation addDependency:self.operation];
}

@end
