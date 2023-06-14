#import <Foundation/Foundation.h>

@interface TeakUserConfiguration : NSObject <NSCopying>

@property (copy, nonatomic) NSString* _Nullable email;
@property (copy, nonatomic) NSString* _Nullable facebookId;
@property (nonatomic) BOOL optOutFacebook __deprecated;
@property (nonatomic) BOOL optOutIdfa;
@property (nonatomic) BOOL optOutPushKey;

- (nonnull NSDictionary*)to_h;

+ (nonnull TeakUserConfiguration*)fromDictionary:(nonnull NSDictionary*)dictionary;
@end
