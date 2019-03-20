#import "TeakMPInt.h"

@interface TeakMPInt ()
@property (readwrite, nonatomic) mp_int mp_int;
@end

@implementation TeakMPInt

+ (nullable TeakMPInt*)MPIntTakingOwnershipOf:(nonnull mp_int*)mp_intToAssume {
  return [[TeakMPInt alloc] initTakingOwnershipOf:mp_intToAssume];
}

- (void)dealloc {
  mp_clear(&_mp_int);
}

- (nullable id)initTakingOwnershipOf:(nonnull mp_int*)mp_intToAssume {
  self = [super init];
  if (self) {
    memcpy(&_mp_int, mp_intToAssume, sizeof(mp_int));
  }
  return self;
}

- (nonnull id)sumWith:(nullable id)other {
  if ([other isKindOfClass:[TeakMPInt class]]) {
    TeakMPInt* mpOther = other;
    mp_int mpSum;
    mp_init(&mpSum);
    if (mp_add(&_mp_int, &mpOther->_mp_int, &mpSum) == MP_OKAY) {
      mp_clear(&_mp_int);
      memcpy(&_mp_int, &mpSum, sizeof(mp_int));
    } else {
      mp_clear(&mpSum);
    }
  }
  return self;
}

- (NSString*)description {
  char buf[16000];
  mp_toradix(&_mp_int, buf, 10);
  return [NSString stringWithUTF8String:buf];
}

- (NSString*)debugDescription {
  return [NSString stringWithFormat:@"sign: %d, digits: %d (%d) %@",
                                    _mp_int.sign, _mp_int.used, _mp_int.alloc, [self description]];
}

@end
