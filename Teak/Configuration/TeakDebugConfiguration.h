#import <Foundation/Foundation.h>

@interface TeakDebugConfiguration : NSObject
@property (nonatomic, readonly) BOOL logLocal;
@property (nonatomic, readonly) BOOL logRemote;

- (id)initWithUserDefaults:(NSUserDefaults*)userDefaults infoDictionary:(NSDictionary*)infoDictionary;
- (void)setLogLocal:(BOOL)logLocal logRemote:(BOOL)logRemote;
@end
