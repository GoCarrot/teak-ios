#import "SKPaymentObserver.h"
#import "PurchaseEvent.h"
#import "Teak+Internal.h"
#import "TeakHelpers.h"
#import "TeakStoreKit2Transaction.h"

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
                                       price:nil
                                    jwsToken:nil
                      rememberAcrossLaunches:NO];
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

// Claims a transaction id for reporting. Returns NO if this id is already being
// reported in this launch, or was reported (and acknowledged by the server) in
// a previous launch. Claims are in-memory only, so a send that never lands is
// retried when the transaction is redelivered on a later launch.
+ (BOOL)claimTransactionId:(NSString*)transactionId {
  @synchronized(ReportedTransactionsMutex) {
    if ([[SKPaymentObserver claimedTransactionIds] containsObject:transactionId]) return NO;
    NSArray* persisted = [[NSUserDefaults standardUserDefaults] arrayForKey:ReportedTransactionsDefaultsKey];
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
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
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
  // Transport failures produce an empty reply; the server's error replies carry another code.
  id code = reply[@"code"];
  return [code isKindOfClass:[NSNumber class]] && [code integerValue] == 200;
}

#pragma mark - Reporting

+ (void)reportPurchaseOfProduct:(NSString*)productId
                  transactionId:(NSString*)transactionId
                   purchaseDate:(NSDate*)purchaseDate
               purchaseDuration:(NSNumber*)purchaseDuration
                         source:(NSString*)source
                          price:(NSDictionary*)price
                       jwsToken:(NSString*)jwsToken
         rememberAcrossLaunches:(BOOL)rememberAcrossLaunches {
  if (productId == nil) return;

  teak_try {
    NSDateFormatter* formatter = [SKPaymentObserver transactionDateFormatter];
    void (^send)(NSDictionary*) = ^(NSDictionary* priceInfo) {
      NSMutableDictionary* fullPayload = [NSMutableDictionary dictionaryWithDictionary:@{
        @"purchase_time" : _([formatter stringFromDate:purchaseDate]),
        @"product_id" : productId,
        @"transaction_identifier" : _(transactionId),
        @"purchase_duration" : _(purchaseDuration)
      }];
      if (jwsToken != nil) {
        fullPayload[@"jws_representation"] = jwsToken;
      }
      [fullPayload addEntriesFromDictionary:priceInfo ?: @{}];
      // The server accepts a purchase without a price but doesn't track it, so only a
      // priced send marks the transaction reported.
      BOOL priced = priceInfo.count > 0;

      // Claim at the send, so a lookup that never returns holds no id.
      if (transactionId != nil && ![SKPaymentObserver claimTransactionId:transactionId]) {
        TeakLog_i(@"purchase.report.duplicate", @{@"source" : source, @"transaction_identifier" : transactionId});
        return;
      }

      NSURL* receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
      NSData* receipt = receiptURL == nil ? nil : [NSData dataWithContentsOfURL:receiptURL];
      fullPayload[@"purchase_token"] = _([receipt base64EncodedStringWithOptions:0]);
      TeakLog_i(@"purchase.report", @{
        @"source" : source,
        @"product_id" : productId,
        @"transaction_identifier" : _(transactionId),
        @"receipt_bytes" : receipt == nil ? [NSNull null] : @(receipt.length),
        @"has_jws" : @(jwsToken != nil)
      });

      [PurchaseEvent purchaseSucceeded:fullPayload
                               onReply:^(NSDictionary* reply) {
                                 if (transactionId == nil) return;
                                 if (![SKPaymentObserver isSuccessfulPurchaseReply:reply] || !priced) {
                                   [SKPaymentObserver releaseTransactionId:transactionId];
                                 } else if (rememberAcrossLaunches) {
                                   [SKPaymentObserver persistReportedTransactionId:transactionId];
                                 }
                               }];
    };

    // A price from the caller is what this transaction cost; the product lookup would only
    // give today's list price.
    if (price.count > 0) {
      TeakLog_i(@"purchase.report.price", @{@"source" : source, @"price_source" : @"caller"});
      send(price);
      return;
    }

    [ProductRequest productRequestForSku:productId
                                callback:^(NSDictionary* priceInfo, SKProductsResponse* unused) {
                                  TeakLog_i(@"purchase.report.price", @{@"source" : source, @"price_source" : priceInfo.count > 0 ? @"storekit" : @"none"});
                                  send(priceInfo);
                                }];
  }
  teak_catch_report;
}

+ (void)reportStoreKit2TransactionJWS:(NSString*)jwsRepresentation {
  teak_try {
    NSDictionary* transaction = [TeakStoreKit2Transaction payloadFromJWS:jwsRepresentation];
    if (transaction == nil) {
      TeakLog_e(@"purchase.report_storekit2.invalid_jws", @"reportStoreKit2Transaction: needs the transaction's jwsRepresentation; this isn't a decodable JWS.");
      return;
    }

    NSString* transactionId = [TeakStoreKit2Transaction transactionIdForTransaction:transaction];
    NSString* skipReason = [TeakStoreKit2Transaction skipReasonForTransaction:transaction];
    if (skipReason != nil) {
      TeakLog_i(@"purchase.report_storekit2.skipped", @{@"reason" : skipReason, @"transaction_identifier" : _(transactionId)});
      return;
    }
    if (transaction[@"transactionReason"] == nil) {
      TeakLog_i(@"purchase.report_storekit2.reason_missing", @{@"transaction_identifier" : transactionId});
    }

    // Xcode's StoreKit Testing restarts transaction ids at 0 when the tester clears them.
    BOOL isXcodeTesting = [transaction[@"environment"] isEqual:@"Xcode"];
    [SKPaymentObserver reportPurchaseOfProduct:transaction[@"productId"]
                                 transactionId:transactionId
                                  purchaseDate:[TeakStoreKit2Transaction purchaseDateForTransaction:transaction]
                              purchaseDuration:nil
                                        source:@"report_storekit2_transaction"
                                         price:[TeakStoreKit2Transaction priceForTransaction:transaction]
                                      jwsToken:jwsRepresentation
                        rememberAcrossLaunches:!isXcodeTesting];
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
