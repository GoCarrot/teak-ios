//  OCMockito by Jon Reid, https://qualitycoding.org/
//  Copyright 2018 Jonathan M. Reid. See LICENSE.txt

#import "MKTAnswer.h"
#import "MKTInvocationMatcher.h"

NS_ASSUME_NONNULL_BEGIN

@interface MKTStubbedInvocationMatcher : MKTInvocationMatcher <MKTAnswer>

- (void)addAnswer:(id<MKTAnswer>)answer;

@end

NS_ASSUME_NONNULL_END
