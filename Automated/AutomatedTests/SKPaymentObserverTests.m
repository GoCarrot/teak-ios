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
static NSUInteger ProductLookups;

@interface SKPaymentObserverTestDoubles : NSObject
@end

@implementation SKPaymentObserverTestDoubles
+ (ProductRequest*)productRequestForSku:(NSString*)sku callback:(ProductRequestCallback)callback {
  ProductLookups++;
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

// The transaction JSON from a sandbox consumable bought with Unity IAP 5 on an iOS 18.7 device,
// as a JWS with a placeholder header and signature (not a captured JWS: only the payload
// segment is read, and the signature isn't verified).
// Teak's public method, reached without importing Teak.h next to these internal headers
// (the framework and source copies of its headers clash in this target).
@protocol TeakStoreKit2Reporting <NSObject>
- (void)reportStoreKit2Transaction:(NSString*)jwsRepresentation;
@end

static id<TeakStoreKit2Reporting> BareTeak(void) {
  // A bare instance: see CLAUDE.md "Creating Teak instances for testing".
  return [[NSClassFromString(@"Teak") alloc] init];
}

static NSString* SandboxJWSWith(NSDictionary* changes, NSArray* removing) {
  NSMutableDictionary* transaction = [@{
    @"transactionId" : @"2000001265157858",
    @"originalTransactionId" : @"2000001265157858",
    @"bundleId" : @"io.teak.app.unity.dev",
    @"productId" : @"io.teak.app.unity.dev.dollar",
    @"purchaseDate" : @1794531516000,
    @"originalPurchaseDate" : @1794531516000,
    @"quantity" : @1,
    @"type" : @"Consumable",
    @"inAppOwnershipType" : @"PURCHASED",
    @"signedDate" : @1794531517446,
    @"environment" : @"Sandbox",
    @"transactionReason" : @"PURCHASE",
    @"storefront" : @"USA",
    @"storefrontId" : @"143441",
    @"price" : @990,
    @"currency" : @"USD"
  } mutableCopy];
  [transaction addEntriesFromDictionary:changes];
  [transaction removeObjectsForKeys:removing];
  NSString* payload = [[NSJSONSerialization dataWithJSONObject:transaction options:0 error:nil] base64EncodedStringWithOptions:0];
  payload = [[[payload stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
      stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
      stringByReplacingOccurrencesOfString:@"=" withString:@""];
  return [NSString stringWithFormat:@"eyJhbGciOiJFUzI1NiJ9.%@.c2lnbmF0dXJl", payload];
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
                                         price:@{@"price_currency_code" : @"USD", @"price_float" : [NSDecimalNumber decimalNumberWithString:@"0.99"]}
                                      jwsToken:@"header.payload.signature"];
  }
  [SKPaymentObserver reportPurchaseOfProduct:@"io.teak.app.unity.dev.dollar"
                               transactionId:@"2000001265157768"
                                purchaseDate:[NSDate date]
                            purchaseDuration:nil
                                      source:@"storekit2"
                                       price:nil
                                    jwsToken:nil];

  SwapClassMethods([ProductRequest class], [SKPaymentObserverTestDoubles class], @selector(productRequestForSku:callback:));
  SwapClassMethods([PurchaseEvent class], [SKPaymentObserverTestDoubles class], @selector(purchaseSucceeded:onReply:));

  NSArray* ids = [ReportedPayloads valueForKey:@"transaction_identifier"];
  XCTAssertEqualObjects(ids, (@[ @"2000001265157858", @"2000001265157768" ]));
  XCTAssertEqualObjects(ReportedPayloads.firstObject[@"jws_representation"], @"header.payload.signature");
  XCTAssertEqualObjects(ReportedPayloads.firstObject[@"price_currency_code"], @"USD", @"caller price is used when StoreKit returns none");
}

- (void)withReportStandIns:(void (^)(void))block {
  ReportedPayloads = [NSMutableArray array];
  ProductLookups = 0;
  SwapClassMethods([ProductRequest class], [SKPaymentObserverTestDoubles class], @selector(productRequestForSku:callback:));
  SwapClassMethods([PurchaseEvent class], [SKPaymentObserverTestDoubles class], @selector(purchaseSucceeded:onReply:));
  block();
  SwapClassMethods([ProductRequest class], [SKPaymentObserverTestDoubles class], @selector(productRequestForSku:callback:));
  SwapClassMethods([PurchaseEvent class], [SKPaymentObserverTestDoubles class], @selector(purchaseSucceeded:onReply:));
}

// The game reports a StoreKit 2 purchase once, and again later, and the StoreKit 1 observer
// also sees it: one send, priced from the JWS without a product lookup.
- (void)testReportedStoreKit2TransactionSendsOncePricedFromTheJWS {
  id<TeakStoreKit2Reporting> teak = BareTeak();
  NSString* jws = SandboxJWSWith(@{}, @[]);
  [self withReportStandIns:^{
    [teak reportStoreKit2Transaction:jws];
    [teak reportStoreKit2Transaction:jws];
    [SKPaymentObserver reportPurchaseOfProduct:@"io.teak.app.unity.dev.dollar"
                                 transactionId:@"2000001265157858"
                                  purchaseDate:[NSDate date]
                              purchaseDuration:nil
                                        source:@"storekit1_observer"
                                         price:nil
                                      jwsToken:nil];
  }];

  XCTAssertEqual(ReportedPayloads.count, 1u);
  NSDictionary* payload = ReportedPayloads.firstObject;
  XCTAssertEqualObjects(payload[@"product_id"], @"io.teak.app.unity.dev.dollar");
  XCTAssertEqualObjects(payload[@"transaction_identifier"], @"2000001265157858");
  XCTAssertEqualObjects(payload[@"jws_representation"], jws);
  XCTAssertEqualObjects(payload[@"price_currency_code"], @"USD");
  XCTAssertEqualObjects(payload[@"price_float"], [NSDecimalNumber decimalNumberWithString:@"0.99"]);
  XCTAssertEqualObjects(payload[@"purchase_time"], @"2026-11-13T00:58:36+0000");
  XCTAssertEqual(ProductLookups, 0u, @"the JWS price is what this transaction cost; no lookup");
}

- (void)testReportedStoreKit2TransactionsThatAreNotPurchasesAreNotSent {
  id<TeakStoreKit2Reporting> teak = BareTeak();
  [self withReportStandIns:^{
    [teak reportStoreKit2Transaction:@"not a jws"];
    [teak reportStoreKit2Transaction:SandboxJWSWith(@{@"transactionReason" : @"RENEWAL"}, @[])];
    [teak reportStoreKit2Transaction:SandboxJWSWith(@{@"revocationDate" : @1794531600000}, @[])];
    [teak reportStoreKit2Transaction:SandboxJWSWith(@{@"inAppOwnershipType" : @"FAMILY_SHARED"}, @[])];
  }];
  XCTAssertEqual(ReportedPayloads.count, 0u);
}

// The transactionReason key may be absent on older OS versions; those purchases still count.
- (void)testReportedStoreKit2TransactionWithoutAReasonIsSent {
  id<TeakStoreKit2Reporting> teak = BareTeak();
  [self withReportStandIns:^{
    [teak reportStoreKit2Transaction:SandboxJWSWith(@{}, @[ @"transactionReason" ])];
  }];
  XCTAssertEqual(ReportedPayloads.count, 1u);
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
