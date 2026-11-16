#import <XCTest/XCTest.h>

#import <objc/runtime.h>

#import "PurchaseEvent.h"
#import "SKPaymentObserver.h"
#import "TeakRaven.h"
#import "TeakStoreKit2Fixtures.h"

// SKPaymentObserver.transactionDateFormatter is private — re-declare for test access.
@interface SKPaymentObserver (Testing)
+ (NSDateFormatter*)transactionDateFormatter;
@end

// TeakRavenReport is defined in TeakRaven.m; dateFormatter is its only method we need.
@interface TeakRavenReport : NSObject
+ (NSDateFormatter*)dateFormatter;
@end

// ProductRequest keeps its callback and active-request list private — re-declare for test access.
@interface ProductRequest (Testing)
@property (copy, nonatomic) ProductRequestCallback callback;
+ (NSMutableArray*)activeProductRequests;
+ (void)addActiveProductRequest:(ProductRequest*)request;
@end

// Teak's public method, reached without importing Teak.h next to these internal headers
// (the framework and source copies of its headers clash in this target).
@protocol TeakStoreKit2Reporting <NSObject>
- (void)reportStoreKit2Transaction:(NSString*)jwsRepresentation;
@end

static id<TeakStoreKit2Reporting> BareTeak(void) {
  return [[NSClassFromString(@"Teak") alloc] init];
}

// Stand-ins for the product lookup and the event post, so a report runs synchronously and
// can be counted without StoreKit or the network.
static NSMutableArray<NSDictionary*>* ReportedPayloads;
static NSUInteger ProductLookups;

@interface SKPaymentObserverTestDoubles : NSObject
@end

@implementation SKPaymentObserverTestDoubles
+ (ProductRequest*)productRequestForSku:(NSString*)sku callback:(ProductRequestCallback)callback {
  ProductLookups++;
  callback(@{@"price_currency_code" : @"EUR", @"price_float" : @1.09}, nil);
  return nil;
}

+ (void)purchaseSucceeded:(NSDictionary*)payload {
  [ReportedPayloads addObject:payload];
}
@end

static void SwapClassMethods(Class original, Class replacement, SEL selector) {
  method_exchangeImplementations(class_getClassMethod(original, selector), class_getClassMethod(replacement, selector));
}

@interface SKPaymentObserverTests : XCTestCase
@end

@implementation SKPaymentObserverTests

- (void)withReportStandIns:(void (^)(void))block {
  ReportedPayloads = [NSMutableArray array];
  ProductLookups = 0;
  SwapClassMethods([ProductRequest class], [SKPaymentObserverTestDoubles class], @selector(productRequestForSku:callback:));
  SwapClassMethods([PurchaseEvent class], [SKPaymentObserverTestDoubles class], @selector(purchaseSucceeded:));
  block();
  SwapClassMethods([ProductRequest class], [SKPaymentObserverTestDoubles class], @selector(productRequestForSku:callback:));
  SwapClassMethods([PurchaseEvent class], [SKPaymentObserverTestDoubles class], @selector(purchaseSucceeded:));
}

#pragma mark - reportStoreKit2Transaction:

// Pins the whole /me/purchase payload for the real device transaction.
- (void)testReportedStoreKit2TransactionPayloadIsExactly {
  id<TeakStoreKit2Reporting> teak = BareTeak();
  NSString* jws = SandboxJWSWith(@{}, @[]);
  [self withReportStandIns:^{
    [teak reportStoreKit2Transaction:jws];
  }];

  NSURL* receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
  NSData* receipt = receiptURL == nil ? nil : [NSData dataWithContentsOfURL:receiptURL];
  NSDictionary* expected = @{
    @"purchase_time" : @"2026-11-13T00:58:36+0000",
    @"product_id" : @"io.teak.app.unity.dev.dollar",
    @"transaction_identifier" : @"2000001265157858",
    @"purchase_token" : receipt == nil ? [NSNull null] : [receipt base64EncodedStringWithOptions:0],
    @"jws_representation" : jws,
    @"price_currency_code" : @"USD",
    @"price_float" : [NSDecimalNumber decimalNumberWithString:@"0.99"]
  };
  XCTAssertEqualObjects(ReportedPayloads, @[ expected ]);
  XCTAssertEqual(ProductLookups, 0u, @"the JWS price is what this transaction cost; no lookup");
}

- (void)testReportedStoreKit2TransactionWithoutAPriceUsesTheProductLookup {
  id<TeakStoreKit2Reporting> teak = BareTeak();
  [self withReportStandIns:^{
    [teak reportStoreKit2Transaction:SandboxJWSWith(@{}, @[ @"price", @"currency" ])];
  }];
  XCTAssertEqual(ProductLookups, 1u);
  XCTAssertEqual(ReportedPayloads.count, 1u);
  XCTAssertEqualObjects(ReportedPayloads.firstObject[@"price_currency_code"], @"EUR");
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

#pragma mark - ProductRequest failure

// A failed SKProductsRequest must still call back, or the purchase is never reported.
- (void)testFailedProductRequestStillCallsBackWithoutPriceInfo {
  ProductRequest* request = [[ProductRequest alloc] init];
  __block NSUInteger calls = 0;
  __block NSDictionary* receivedInfo = nil;
  __block SKProductsResponse* receivedResponse = nil;
  request.callback = ^(NSDictionary* priceInfo, SKProductsResponse* response) {
    calls++;
    receivedInfo = priceInfo;
    receivedResponse = response;
  };
  [ProductRequest addActiveProductRequest:request];

  NSError* error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil];
  [(id<SKRequestDelegate>)request request:nil didFailWithError:error];

  XCTAssertEqual(calls, 1u);
  XCTAssertEqualObjects(receivedInfo, @{});
  XCTAssertNil(receivedResponse);
  XCTAssertFalse([[ProductRequest activeProductRequests] containsObject:request]);
}

#pragma mark - Date formatting

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
