#pragma once

#import "TeakPushState.h"

@class TeakPushStateChainEntry;

@interface TeakPushState ()

@property (strong, atomic) NSArray* stateChain;
@property (strong, nonatomic) NSOperationQueue* operationQueue;

- (TeakPushStateChainEntry*)determineCurrentPushStateBlocking;
@end
