#import "TeakOperationTestDriver.h"

@implementation TeakOperationTestDriver

- (TeakOperationResult*)runSync:(TeakOperation*)op {
  NSOperationQueue* queue = [[NSOperationQueue alloc] init];
  [queue addOperation:op];
  [queue waitUntilAllOperationsAreFinished];
  return (TeakOperationResult*)[op result];
}

- (NSDictionary*)requestParamsFor:(TeakOperation*)op {
  NSInvocation* inv = op.invocation;
  __unsafe_unretained NSDictionary* requestParams;
  [inv getArgument:&requestParams atIndex:2];
  return requestParams;
}

@end
