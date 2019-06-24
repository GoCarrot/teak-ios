//  OCMockito by Jon Reid, https://qualitycoding.org/
//  Copyright 2018 Jonathan M. Reid. See LICENSE.txt

#import "MKTVerificationMode.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MKTExactTimes : NSObject <MKTVerificationMode>

- (instancetype)initWithCount:(NSUInteger)wantedNumberOfInvocations NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
