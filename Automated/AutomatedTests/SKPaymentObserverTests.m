#import <XCTest/XCTest.h>

#import <objc/runtime.h>

#import "PurchaseEvent.h"
#import "SKPaymentObserver.h"
#import "TeakRaven.h"

// SKPaymentObserver.transactionDateFormatter is private — re-declare for test access.
@interface SKPaymentObserver (Testing)
+ (NSDateFormatter*)transactionDateFormatter;
+ (BOOL)claimTransactionId:(NSString*)transactionId;
+ (void)releaseTransactionId:(NSString*)transactionId;
+ (void)persistReportedTransactionId:(NSString*)transactionId;
+ (void)clearClaimedTransactionIds;
+ (BOOL)isSuccessfulPurchaseReply:(NSDictionary*)reply;
@end

static NSString* const ReportedTransactionsDefaultsKey = @"TeakReportedTransactionIds";

// TeakRavenReport is defined in TeakRaven.m; dateFormatter is its only method we need.
@interface TeakRavenReport : NSObject
+ (NSDateFormatter*)dateFormatter;
@end

@interface SKPaymentObserverTests : XCTestCase
@end

// Stand-ins for the product lookup and the event post, so a report runs synchronously and
// can be counted without StoreKit or the network.
static NSMutableArray<NSDictionary*>* ReportedPayloads;

@interface SKPaymentObserverTestDoubles : NSObject
@end

@implementation SKPaymentObserverTestDoubles
+ (ProductRequest*)productRequestForSku:(NSString*)sku callback:(ProductRequestCallback)callback {
  callback(@{}, nil);
  return nil;
}

+ (void)purchaseSucceeded:(NSDictionary*)payload onReply:(PurchaseEventReply)onReply {
  [ReportedPayloads addObject:payload];
}
@end

static void SwapClassMethods(Class original, Class replacement, SEL selector) {
  method_exchangeImplementations(class_getClassMethod(original, selector), class_getClassMethod(replacement, selector));
}

@implementation SKPaymentObserverTests

- (void)setUp {
  [SKPaymentObserver clearClaimedTransactionIds];
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:ReportedTransactionsDefaultsKey];
}

- (void)tearDown {
  [SKPaymentObserver clearClaimedTransactionIds];
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:ReportedTransactionsDefaultsKey];
}

// The StoreKit 1 observer and the report-purchase hook both see an SK1 purchase;
// only the first claim may report it.
- (void)testSecondClaimInSameLaunchIsRejected {
  XCTAssertTrue([SKPaymentObserver claimTransactionId:@"2000000123"]);
  XCTAssertFalse([SKPaymentObserver claimTransactionId:@"2000000123"]);
  XCTAssertTrue([SKPaymentObserver claimTransactionId:@"2000000124"]);
}

// A send that never landed must be retried when the transaction is redelivered
// on a later launch, so an unacknowledged claim must not survive the launch.
- (void)testUnacknowledgedClaimDoesNotSurviveRelaunch {
  XCTAssertTrue([SKPaymentObserver claimTransactionId:@"2000000123"]);
  [SKPaymentObserver clearClaimedTransactionIds]; // models a relaunch
  XCTAssertTrue([SKPaymentObserver claimTransactionId:@"2000000123"]);
}

// Once the server acknowledged the report, redelivery on a later launch is skipped.
- (void)testAcknowledgedTransactionIsRejectedAfterRelaunch {
  XCTAssertTrue([SKPaymentObserver claimTransactionId:@"2000000123"]);
  [SKPaymentObserver persistReportedTransactionId:@"2000000123"];
  [SKPaymentObserver clearClaimedTransactionIds]; // models a relaunch
  XCTAssertFalse([SKPaymentObserver claimTransactionId:@"2000000123"]);
}

// A failed send releases the claim so a redelivery in the same launch can retry.
- (void)testReleasedClaimCanBeReclaimed {
  XCTAssertTrue([SKPaymentObserver claimTransactionId:@"2000000123"]);
  [SKPaymentObserver releaseTransactionId:@"2000000123"];
  XCTAssertTrue([SKPaymentObserver claimTransactionId:@"2000000123"]);
}

- (void)testPersistedTransactionIdsAreBounded {
  for (int i = 0; i < 100; i++) {
    [SKPaymentObserver persistReportedTransactionId:[NSString stringWithFormat:@"%d", i]];
  }
  NSArray* persisted = [[NSUserDefaults standardUserDefaults] arrayForKey:ReportedTransactionsDefaultsKey];
  XCTAssertEqual(persisted.count, 64u);
  XCTAssertEqualObjects(persisted.lastObject, @"99");
  XCTAssertTrue([SKPaymentObserver claimTransactionId:@"0"], @"oldest ids age out");
}

- (void)testPurchaseReplyClassification {
  XCTAssertTrue([SKPaymentObserver isSuccessfulPurchaseReply:@{@"code" : @200}]);
  XCTAssertFalse([SKPaymentObserver isSuccessfulPurchaseReply:@{}], @"transport failure yields an empty reply");
  XCTAssertFalse([SKPaymentObserver isSuccessfulPurchaseReply:@{@"error" : @{@"code" : @404}}]);
}

// IAP 5 finishes each StoreKit 2 transaction twice, and a purchase can reach Teak from
// more than one path; every report of one transaction id after the first must be dropped.
- (void)testRepeatedReportsOfOneTransactionSendOnce {
  ReportedPayloads = [NSMutableArray array];
  SwapClassMethods([ProductRequest class], [SKPaymentObserverTestDoubles class], @selector(productRequestForSku:callback:));
  SwapClassMethods([PurchaseEvent class], [SKPaymentObserverTestDoubles class], @selector(purchaseSucceeded:onReply:));

  for (NSString* source in @[ @"storekit2", @"storekit2", @"storekit1_observer" ]) {
    [SKPaymentObserver reportPurchaseOfProduct:@"io.teak.app.unity.dev.dollar"
                                 transactionId:@"2000001265157858"
                                  purchaseDate:[NSDate date]
                              purchaseDuration:nil
                                        source:source
                                 fallbackPrice:@{@"price_currency_code" : @"USD", @"price_float" : [NSDecimalNumber decimalNumberWithString:@"0.99"]}
                                      jwsToken:@"header.payload.signature"];
  }
  [SKPaymentObserver reportPurchaseOfProduct:@"io.teak.app.unity.dev.dollar"
                               transactionId:@"2000001265157768"
                                purchaseDate:[NSDate date]
                            purchaseDuration:nil
                                      source:@"storekit2"
                               fallbackPrice:nil
                                    jwsToken:nil];

  SwapClassMethods([ProductRequest class], [SKPaymentObserverTestDoubles class], @selector(productRequestForSku:callback:));
  SwapClassMethods([PurchaseEvent class], [SKPaymentObserverTestDoubles class], @selector(purchaseSucceeded:onReply:));

  NSArray* ids = [ReportedPayloads valueForKey:@"transaction_identifier"];
  XCTAssertEqualObjects(ids, (@[ @"2000001265157858", @"2000001265157768" ]));
  XCTAssertEqualObjects(ReportedPayloads.firstObject[@"jws_representation"], @"header.payload.signature");
  XCTAssertEqualObjects(ReportedPayloads.firstObject[@"price_currency_code"], @"USD", @"caller price is used when StoreKit returns none");
}

// Verifies purchase_time uses en_US_POSIX so Arabic-locale devices don't produce
// Eastern-Arabic numerals the server can't parse (ArgumentError: mon out of range).
- (void)testPurchaseTimeDateFormatterProducesLocaleIndependentOutput {
  NSDate* date = [NSDate dateWithTimeIntervalSince1970:1705319445]; // 2024-01-15T11:50:45 UTC
  NSString* formatted = [[SKPaymentObserver transactionDateFormatter] stringFromDate:date];
  XCTAssertEqualObjects(formatted, @"2024-01-15T11:50:45+0000",
                        @"purchase_time must use ASCII digits regardless of device locale");
}

// Verifies the Sentry timestamp formatter (TeakRaven) has the same en_US_POSIX fix applied.
// en_US_POSIX pins digits to ASCII without changing the ISO8601 format Sentry expects.
- (void)testRavenDateFormatterProducesLocaleIndependentOutput {
  NSDate* date = [NSDate dateWithTimeIntervalSince1970:1705319445]; // 2024-01-15T11:50:45 UTC
  NSString* formatted = [[TeakRavenReport dateFormatter] stringFromDate:date];
  XCTAssertEqualObjects(formatted, @"2024-01-15T11:50:45",
                        @"Sentry timestamp must use ASCII digits regardless of device locale");
}

@end
