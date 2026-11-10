#pragma once

#import "SKPaymentObserver.h"

@interface ProductRequest ()
@property (copy, nonatomic) ProductRequestCallback callback;
@property (strong, nonatomic) SKProductsRequest* productsRequest;

// Defined in SKPaymentObserver.m; declared here so the race tests can drive the synchronized mutation directly.
+ (void)addActiveProductRequest:(ProductRequest*)request;
+ (void)removeActiveProductRequest:(ProductRequest*)request;
@end
