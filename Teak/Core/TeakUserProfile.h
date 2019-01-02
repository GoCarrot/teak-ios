#import "TeakRequest+Internal.h"

@class TeakSession;

@interface TeakUserProfile : TeakRequest

- (TeakUserProfile*)initForSession:(TeakSession*)session withDictionary:(NSDictionary*)dictionary;
- (void)setNumericAttribute:(double)value forKey:(NSString*)key;
- (void)setStringAttribute:(NSString*)value forKey:(NSString*)key;
@end
