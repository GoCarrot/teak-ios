/* Teak -- Copyright (C) 2017 GoCarrot Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "SKPaymentObserver.h"
#import "PurchaseEvent.h"
#import "Teak+Internal.h"
#import <StoreKit/StoreKit.h>

@interface SKPaymentObserver () <SKPaymentTransactionObserver, TeakEventHandler>
- (void)paymentQueue:(SKPaymentQueue*)queue updatedTransactions:(NSArray<SKPaymentTransaction*>*)transactions;
@end

typedef void (^ProductRequestCallback)(NSDictionary* priceInfo, SKProductsResponse* response);

@interface ProductRequest : NSObject <SKProductsRequestDelegate>
@property (copy, nonatomic) ProductRequestCallback callback;
@property (strong, nonatomic) SKProductsRequest* productsRequest;

+ (ProductRequest*)productRequestForSku:(NSString*)sku callback:(ProductRequestCallback)callback;

- (void)productsRequest:(SKProductsRequest*)request didReceiveResponse:(SKProductsResponse*)response;
@end

@implementation SKPaymentObserver
- (id)initForSomething:(id _Nullable)foo {
  self = [super init];
  if (self) {
    [TeakEvent addEventHandler:self];

    // Register default purchase deep link
    // TODO: Should this be here, or somewhere else
    [TeakLink registerRoute:@"/teak_internal/store/:sku"
                       name:@""
                description:@""
                      block:^(NSDictionary* _Nonnull parameters) {
                        [ProductRequest productRequestForSku:parameters[@"sku"]
                                                    callback:^(NSDictionary* unused, SKProductsResponse* response) {
                                                      if (response.products.count > 0) {
                                                        SKProduct* product = [response.products objectAtIndex:0];

                                                        SKMutablePayment* payment = [SKMutablePayment paymentWithProduct:product];
                                                        payment.quantity = 1;
                                                        [[SKPaymentQueue defaultQueue] addPayment:payment];
                                                      }
                                                    }];
                      }];
  }
  return self;
}

- (void)dealloc {
  [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

- (void)transactionPurchased:(SKPaymentTransaction*)transaction {
  if (transaction == nil || transaction.payment == nil || transaction.payment.productIdentifier == nil) return;

  teak_try {
    teak_log_breadcrumb(@"Building date formatter");
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    [formatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mmZ"];

    teak_log_breadcrumb(@"Getting info from App Store receipt");
    NSURL* receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData* receipt = [NSData dataWithContentsOfURL:receiptURL];

    [ProductRequest productRequestForSku:transaction.payment.productIdentifier
                                callback:^(NSDictionary* priceInfo, SKProductsResponse* unused) {
                                  teak_log_breadcrumb(@"Building payload");
                                  NSMutableDictionary* fullPayload = [NSMutableDictionary dictionaryWithDictionary:@{
                                    @"purchase_time" : [formatter stringFromDate:transaction.transactionDate],
                                    @"product_id" : transaction.payment.productIdentifier,
                                    @"purchase_token" : [receipt base64EncodedStringWithOptions:0]
                                  }];

                                  if (priceInfo != nil) {
                                    [fullPayload addEntriesFromDictionary:priceInfo];
                                  }

                                  [PurchaseEvent purchaseSucceeded:fullPayload];
                                }];
  }
  teak_catch_report;
}

- (void)transactionFailed:(SKPaymentTransaction*)transaction {
  if (transaction == nil || transaction.payment == nil) return;

  teak_try {
    teak_log_breadcrumb(@"Determining status");
    NSString* errorString = @"unknown";
    switch (transaction.error.code) {
      case SKErrorClientInvalid:
        errorString = @"client_invalid";
        break;
      case SKErrorPaymentCancelled:
        errorString = @"payment_canceled";
        break;
      case SKErrorPaymentInvalid:
        errorString = @"payment_invalid";
        break;
      case SKErrorPaymentNotAllowed:
        errorString = @"payment_not_allowed";
        break;
      case SKErrorStoreProductNotAvailable:
        errorString = @"store_product_not_available";
        break;
      default:
        break;
    }
    teak_log_data_breadcrumb(@"Got transaction error code", @{@"transaction.error.code" : errorString});

    NSDictionary* payload = @{
      @"product_id" : _(transaction.payment.productIdentifier),
      @"error_string" : errorString
    };
    [PurchaseEvent purchaseFailed:payload];
  }
  teak_catch_report;
}

- (void)paymentQueue:(SKPaymentQueue*)queue updatedTransactions:(NSArray<SKPaymentTransaction*>*)transactions {
  for (SKPaymentTransaction* transaction in transactions) {
    switch (transaction.transactionState) {
      case SKPaymentTransactionStatePurchased:
        [self transactionPurchased:transaction];
        break;
      case SKPaymentTransactionStateFailed:
        [self transactionFailed:transaction];
        break;
      default:
        break;
    }
  }
}

- (void)handleEvent:(TeakEvent* _Nonnull)event {
  if (event.type == LifecycleFinishedLaunching) {
    [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
  }
}

@end

@implementation ProductRequest

+ (nonnull NSMutableArray*)activeProductRequests {
  static NSMutableArray* array = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    array = [[NSMutableArray alloc] init];
  });
  return array;
}

+ (ProductRequest*)productRequestForSku:(NSString*)sku callback:(ProductRequestCallback)callback {
  ProductRequest* ret = [[ProductRequest alloc] init];
  ret.callback = callback;
  ret.productsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithObject:sku]];
  ret.productsRequest.delegate = ret;
  [ret.productsRequest start];
  [[ProductRequest activeProductRequests] addObject:ret];
  return ret;
}

- (void)productsRequest:(SKProductsRequest*)request didReceiveResponse:(SKProductsResponse*)response {
  if (response != nil && response.products != nil && response.products.count > 0) {
    teak_try {
      teak_log_breadcrumb(@"Collecting product response info");
      SKProduct* product = [response.products objectAtIndex:0];
      NSLocale* priceLocale = product.priceLocale;
      NSString* currencyCode = [priceLocale objectForKey:NSLocaleCurrencyCode];
      NSDecimalNumber* price = product.price;

      self.callback(@{@"price_currency_code" : _(currencyCode), @"price_float" : price}, response);
    }
    teak_catch_report;
  } else {
    self.callback(@{}, nil);
  }
  [[ProductRequest activeProductRequests] removeObject:self];
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<%@: %p> products-request: %@", NSStringFromClass([self class]), self, self.productsRequest];
}

@end
