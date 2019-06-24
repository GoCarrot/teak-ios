//  OCMockito by Jon Reid, https://qualitycoding.org/
//  Copyright 2018 Jonathan M. Reid. See LICENSE.txt
//  Contribution by Emile Cantin

#import "MKTVerificationMode.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MKTAtMostTimes : NSObject <MKTVerificationMode>

- (instancetype)initWithMaximumCount:(NSUInteger)maxNumberOfInvocations NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
