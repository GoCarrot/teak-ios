#import <Foundation/Foundation.h>

#import "3rdParty/libtommath/tommath.h"

@interface TeakMPInt : NSObject
@property (readonly, nonatomic) mp_int mp_int;

+ (nullable TeakMPInt*)MPIntTakingOwnershipOf:(nonnull mp_int*)mp_intToAssume;

- (nullable id)initTakingOwnershipOf:(nonnull mp_int*)mp_intToAssume;
- (nonnull id)sumWith:(nullable id)other;
@end
