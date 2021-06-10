#import <Foundation/Foundation.h>

@interface TeakWaitForDeepLink : NSObject

@property (nonatomic, readonly) BOOL hasBeenAdded;

- (nullable id)init;
- (BOOL)addToQueue:(nonnull NSOperationQueue*)queue;
- (void)addAsDependency:(nonnull NSOperation*)operation;
@end
