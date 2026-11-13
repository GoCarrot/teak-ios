#import "SKPaymentObserver.h"
#import "PurchaseEvent.h"
#import "Teak+Internal.h"
#import "TeakHelpers.h"

#define _(_id) TeakValueOrNSNull(_id)

static NSString* const ProductRequestActiveRequestsMutex = @"io.teak.sdk.productRequestActiveRequestsMutex";

@interface SKPaymentObserver () <SKPaymentTransactionObserver, TeakEventHandler>
@property (nonatomic) NSTimeInterval paymentStart;

- (void)paymentQueue:(SKPaymentQueue*)queue updatedTransactions:(NSArray<SKPaymentTransaction*>*)transactions;
@end

@interface ProductRequest ()
@property (copy, nonatomic) ProductRequestCallback callback;
@property (strong, nonatomic) SKProductsRequest* productsRequest;
@end

@implementation SKPaymentObserver

+ (NSDateFormatter*)transactionDateFormatter {
  NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
  [formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
  [formatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
  [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];
  return formatter;
}

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

  NSNumber* purchaseDuration = [NSNumber numberWithDouble:[[NSDate date] timeIntervalSince1970] - self.paymentStart];
  TeakLog_i(@"transaction.purchased", @{@"purchase_duration" : _(purchaseDuration)});

  [SKPaymentObserver reportPurchaseOfProduct:transaction.payment.productIdentifier
                               transactionId:transaction.transactionIdentifier
                                purchaseDate:transaction.transactionDate
                            purchaseDuration:purchaseDuration
                                      source:@"storekit1_observer"
                               fallbackPrice:nil
                                    jwsToken:nil];
}

#pragma mark - Reported transaction tracking

static NSString* const ReportedTransactionsMutex = @"io.teak.sdk.reportedTransactionsMutex";
static NSString* const ReportedTransactionsDefaultsKey = @"TeakReportedTransactionIds";
static const NSUInteger ReportedTransactionsMaxPersisted = 64;

+ (NSMutableSet<NSString*>*)claimedTransactionIds {
  static NSMutableSet* set = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    set = [[NSMutableSet alloc] init];
  });
  return set;
}

+ (NSUserDefaults*)reportedTransactionDefaults {
  return [NSUserDefaults standardUserDefaults];
}

// Claims a transaction id for reporting. Returns NO if this id is already being
// reported in this launch, or was reported (and acknowledged by the server) in
// a previous launch. Claims are in-memory only, so a send that never lands is
// retried when the transaction is redelivered on a later launch.
+ (void)clearClaimedTransactionIds {
  @synchronized(ReportedTransactionsMutex) {
    [[SKPaymentObserver claimedTransactionIds] removeAllObjects];
  }
}

+ (BOOL)claimTransactionId:(NSString*)transactionId {
  @synchronized(ReportedTransactionsMutex) {
    if ([[SKPaymentObserver claimedTransactionIds] containsObject:transactionId]) return NO;
    NSArray* persisted = [[SKPaymentObserver reportedTransactionDefaults] arrayForKey:ReportedTransactionsDefaultsKey];
    if ([persisted containsObject:transactionId]) return NO;
    [[SKPaymentObserver claimedTransactionIds] addObject:transactionId];
    return YES;
  }
}

+ (void)releaseTransactionId:(NSString*)transactionId {
  @synchronized(ReportedTransactionsMutex) {
    [[SKPaymentObserver claimedTransactionIds] removeObject:transactionId];
  }
}

+ (void)persistReportedTransactionId:(NSString*)transactionId {
  @synchronized(ReportedTransactionsMutex) {
    NSUserDefaults* defaults = [SKPaymentObserver reportedTransactionDefaults];
    NSMutableArray* persisted = [NSMutableArray arrayWithArray:[defaults arrayForKey:ReportedTransactionsDefaultsKey] ?: @[]];
    if ([persisted containsObject:transactionId]) return;
    [persisted addObject:transactionId];
    while (persisted.count > ReportedTransactionsMaxPersisted) {
      [persisted removeObjectAtIndex:0];
    }
    [defaults setObject:persisted forKey:ReportedTransactionsDefaultsKey];
  }
}

+ (BOOL)isSuccessfulPurchaseReply:(NSDictionary*)reply {
  // Transport failures and unparseable bodies produce an empty reply.
  if (reply == nil || reply.count == 0) return NO;
  if (reply[@"error"] != nil && reply[@"error"] != [NSNull null]) return NO;
  return YES;
}

#pragma mark - Reporting

+ (void)reportPurchaseOfProduct:(NSString*)productId
                  transactionId:(NSString*)transactionId
                   purchaseDate:(NSDate*)purchaseDate
               purchaseDuration:(NSNumber*)purchaseDuration
                         source:(NSString*)source
                  fallbackPrice:(NSDictionary*)fallbackPrice
                       jwsToken:(NSString*)jwsToken {
  if (productId == nil) return;

  teak_try {
    // Claim synchronously, ahead of the async price lookup, so two paths
    // reporting the same transaction can't both pass the check.
    if (transactionId != nil && ![SKPaymentObserver claimTransactionId:transactionId]) {
      TeakLog_i(@"purchase.report.duplicate", @{@"source" : source, @"transaction_identifier" : transactionId});
      return;
    }

    teak_log_breadcrumb(@"Getting info from App Store receipt");
    NSURL* receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData* receipt = receiptURL == nil ? nil : [NSData dataWithContentsOfURL:receiptURL];

    TeakLog_i(@"purchase.report", @{
      @"source" : source,
      @"product_id" : productId,
      @"transaction_identifier" : _(transactionId),
      @"receipt_bytes" : receipt == nil ? [NSNull null] : @(receipt.length),
      @"has_jws" : @(jwsToken != nil)
    });

    NSDateFormatter* formatter = [SKPaymentObserver transactionDateFormatter];
    [ProductRequest productRequestForSku:productId
                                callback:^(NSDictionary* priceInfo, SKProductsResponse* unused) {
                                  teak_log_breadcrumb(@"Building payload");
                                  NSMutableDictionary* fullPayload = [NSMutableDictionary dictionaryWithDictionary:@{
                                    @"purchase_time" : _([formatter stringFromDate:purchaseDate]),
                                    @"product_id" : productId,
                                    @"transaction_identifier" : _(transactionId),
                                    @"purchase_token" : _([receipt base64EncodedStringWithOptions:0]),
                                    @"purchase_duration" : _(purchaseDuration)
                                  }];
                                  if (jwsToken != nil) {
                                    fullPayload[@"jws_representation"] = jwsToken;
                                  }

                                  NSString* priceSource = @"none";
                                  if (priceInfo.count > 0) {
                                    [fullPayload addEntriesFromDictionary:priceInfo];
                                    priceSource = @"storekit";
                                  } else if (fallbackPrice.count > 0) {
                                    [fullPayload addEntriesFromDictionary:fallbackPrice];
                                    priceSource = @"caller";
                                  }
                                  TeakLog_i(@"purchase.report.price", @{@"source" : source, @"price_source" : priceSource});

                                  [PurchaseEvent purchaseSucceeded:fullPayload
                                                           onReply:^(NSDictionary* reply) {
                                                             if (transactionId == nil) return;
                                                             if ([SKPaymentObserver isSuccessfulPurchaseReply:reply]) {
                                                               [SKPaymentObserver persistReportedTransactionId:transactionId];
                                                             } else {
                                                               [SKPaymentObserver releaseTransactionId:transactionId];
                                                             }
                                                           }];
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

+ (void)addActiveProductRequest:(ProductRequest*)request {
  @synchronized(ProductRequestActiveRequestsMutex) {
    [[ProductRequest activeProductRequests] addObject:request];
  }
}

+ (void)removeActiveProductRequest:(ProductRequest*)request {
  @synchronized(ProductRequestActiveRequestsMutex) {
    [[ProductRequest activeProductRequests] removeObject:request];
  }
}

+ (ProductRequest*)productRequestForSku:(NSString*)sku callback:(ProductRequestCallback)callback {
  ProductRequest* ret = [[ProductRequest alloc] init];
  ret.callback = callback;
  ret.productsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithObject:sku]];
  ret.productsRequest.delegate = ret;
  [ret.productsRequest start];
  [ProductRequest addActiveProductRequest:ret];
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
  [ProductRequest removeActiveProductRequest:self];
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<%@: %p> products-request: %@", NSStringFromClass([self class]), self, self.productsRequest];
}

@end
