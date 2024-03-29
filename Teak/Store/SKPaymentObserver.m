#import "SKPaymentObserver.h"
#import "PurchaseEvent.h"
#import "Teak+Internal.h"

@interface SKPaymentObserver () <SKPaymentTransactionObserver, TeakEventHandler>
@property (nonatomic) NSTimeInterval paymentStart;

- (void)paymentQueue:(SKPaymentQueue*)queue updatedTransactions:(NSArray<SKPaymentTransaction*>*)transactions;
@end

@interface ProductRequest ()
@property (copy, nonatomic) ProductRequestCallback callback;
@property (strong, nonatomic) SKProductsRequest* productsRequest;
@end

@implementation SKPaymentObserver
- (id)init {
  self = [super init];
  if (self) {
    [TeakEvent addEventHandler:self];
  }
  return self;
}

- (void)dealloc {
  [[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
}

- (void)transactionStarted:(SKPaymentTransaction*)transaction {
  self.paymentStart = [[NSDate date] timeIntervalSince1970];
  TeakLog_i(@"transaction.started", @{@"timestamp" : [NSNumber numberWithDouble:self.paymentStart]});
}

- (void)transactionPurchased:(SKPaymentTransaction*)transaction {
  if (transaction == nil || transaction.payment == nil || transaction.payment.productIdentifier == nil) return;

  teak_try {
    NSNumber* purchaseDuration = [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970] - self.paymentStart];
    TeakLog_i(@"transaction.purchased", @{@"purchase_duration" : _(purchaseDuration)});

    teak_log_breadcrumb(@"Building date formatter");
    NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
    [formatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
    [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];

    teak_log_breadcrumb(@"Getting info from App Store receipt");
    NSURL* receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData* receipt = receiptURL == nil ? nil : [NSData dataWithContentsOfURL:receiptURL];

    [ProductRequest productRequestForSku:transaction.payment.productIdentifier
                                callback:^(NSDictionary* priceInfo, SKProductsResponse* unused) {
                                  teak_log_breadcrumb(@"Building payload");
                                  NSMutableDictionary* fullPayload = [NSMutableDictionary dictionaryWithDictionary:@{
                                    @"purchase_time" : _([formatter stringFromDate:transaction.transactionDate]),
                                    @"product_id" : transaction.payment.productIdentifier,
                                    @"transaction_identifier" : _(transaction.transactionIdentifier),
                                    @"purchase_token" : _([receipt base64EncodedStringWithOptions:0]),
                                    @"purchase_duration" : _(purchaseDuration)
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
    NSNumber* purchaseDuration = [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970] - self.paymentStart];
    TeakLog_i(@"transaction.canceled", @{@"purchase_duration" : _(purchaseDuration)});

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
      @"error_string" : errorString,
      @"purchase_duration" : _(purchaseDuration)
    };
    [PurchaseEvent purchaseFailed:payload];
  }
  teak_catch_report;
}

- (void)paymentQueue:(SKPaymentQueue*)queue updatedTransactions:(NSArray<SKPaymentTransaction*>*)transactions {
  TeakUnused(queue);

  for (SKPaymentTransaction* transaction in transactions) {
    switch (transaction.transactionState) {
      case SKPaymentTransactionStatePurchasing:
        [self transactionStarted:transaction];
        break;
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
      teak_log_breadcrumb(([NSString stringWithFormat:@"Product: %@", product]));

      NSLocale* priceLocale = product.priceLocale;
      teak_log_breadcrumb(([NSString stringWithFormat:@"Product Price Locale: %@", priceLocale]));

      NSString* currencyCode = [priceLocale objectForKey:NSLocaleCurrencyCode];
      teak_log_breadcrumb(([NSString stringWithFormat:@"Product Currency Code: %@", currencyCode]));

      NSDecimalNumber* price = product.price;
      teak_log_breadcrumb(([NSString stringWithFormat:@"Product Price: %@", price]));

      self.callback(@{@"price_currency_code" : _(currencyCode), @"price_float" : _(price)}, response);
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
