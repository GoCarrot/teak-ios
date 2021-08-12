#import <Foundation/Foundation.h>

@interface TeakUserConfiguration : NSObject

@property (copy, nonatomic) NSString* _Nullable email;
@property (copy, nonatomic) NSString* _Nullable facebookId;
@property (nonatomic) BOOL optOutFacebook __deprecated;
@property (nonatomic) BOOL optOutIdfa;
@property (nonatomic) BOOL optOutPushKey;

@end
