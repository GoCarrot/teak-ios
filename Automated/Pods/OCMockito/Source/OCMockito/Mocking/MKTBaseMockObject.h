//  OCMockito by Jon Reid, https://qualitycoding.org/
//  Copyright 2018 Jonathan M. Reid. See LICENSE.txt

#import "MKTNonObjectArgumentMatching.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MKTBaseMockObject : NSProxy <MKTNonObjectArgumentMatching>

+ (BOOL)isMockObject:(id)object;

- (instancetype)init;
- (void)stopMocking;

@end

NS_ASSUME_NONNULL_END
