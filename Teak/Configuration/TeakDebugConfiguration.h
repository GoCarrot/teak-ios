#import <Foundation/Foundation.h>

@interface TeakDebugConfiguration : NSObject
@property (nonatomic, readonly) BOOL logLocal;
@property (nonatomic, readonly) BOOL logRemote;

- (void)setLogLocal:(BOOL)logLocal logRemote:(BOOL)logRemote;
@end
