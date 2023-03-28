#import <Foundation/Foundation.h>

@interface TeakUserConfiguration : NSObject <NSCopying>

@property (copy, nonatomic) NSString* _Nullable email;
@property (copy, nonatomic) NSString* _Nullable facebookId;
@property (nonatomic) BOOL optOutFacebook __deprecated_msg("");
@property (nonatomic) BOOL optOutIdfa;
@property (nonatomic) BOOL optOutPushKey;

- (nonnull NSDictionary*)to_h;
@end
