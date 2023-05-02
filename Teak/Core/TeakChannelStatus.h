#import <Foundation/Foundation.h>

@interface TeakChannelStatus : NSObject
@property (strong, nonatomic, readonly) NSString* _Nonnull state;
@property (strong, nonatomic, readonly) NSDictionary* _Nullable categories;
@property (nonatomic, readonly) BOOL deliveryFault;

+ (nonnull TeakChannelStatus*)unknown;

- (nullable id)initWithDictionary:(nonnull NSDictionary*)dict;
- (nonnull NSDictionary*)toDictionary;
@end
