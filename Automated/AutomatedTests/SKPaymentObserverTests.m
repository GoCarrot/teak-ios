#import <XCTest/XCTest.h>

#import <objc/runtime.h>

#import "PurchaseEvent.h"
#import "SKPaymentObserver.h"
#import "TeakCore.h"
#import "TeakRaven.h"
#import "TeakRequest.h"
#import "TeakSession.h"
#import "TeakStoreKit2Fixtures.h"

@import OCHamcrest;
@import OCMockito;

// Private SKPaymentObserver methods, re-declared for test access.
@interface SKPaymentObserver (Testing)
+ (NSDateFormatter*)transactionDateFormatter;
+ (NSMutableSet<NSString*>*)claimedTransactionIds;
+ (BOOL)claimTransactionId:(NSString*)transactionId;
+ (void)persistReportedTransactionId:(NSString*)transactionId;
- (void)transactionPurchased:(SKPaymentTransaction*)transaction;
@end

static NSString* const ReportedTransactionsDefaultsKey = @"TeakReportedTransactionIds";

// Forgets this launch's claims, as a relaunch would. The tests are single-threaded.
static void ClearClaimedTransactionIds(void) {
  [[SKPaymentObserver claimedTransactionIds] removeAllObjects];
}

// TeakRavenReport is defined in TeakRaven.m; dateFormatter is its only method we need.
@interface TeakRavenReport : NSObject
+ (NSDateFormatter*)dateFormatter;
@end

// Teak's public method, reached without importing Teak.h next to these internal headers
// (the framework and source copies of its headers clash in this target).
@protocol TeakStoreKit2Reporting <NSObject>
- (void)reportStoreKit2Transaction:(NSString*)jwsRepresentation;
@end

static id<TeakStoreKit2Reporting> BareTeak(void) {
  return [[NSClassFromString(@"Teak") alloc] init];
}

@interface SKPaymentObserverTests : XCTestCase
@end

// Stand-ins for the product lookup and the event post, so a report runs synchronously and
// can be counted without StoreKit or the network.
static NSMutableArray<NSDictionary*>* ReportedPayloads;
static NSUInteger ProductLookups;
static BOOL LookupCallsBack;           // NO models a lookup that never returns
static NSDictionary* LookupPriceInfo;  // what a returning lookup hands back
static NSDictionary* PurchaseReply;    // nil: the send never gets a reply

@interface SKPaymentObserverTestDoubles : NSObject
@end

@implementation SKPaymentObserverTestDoubles
+ (ProductRequest*)productRequestForSku:(NSString*)sku callback:(ProductRequestCallback)callback {
  ProductLookups++;
  if (LookupCallsBack) callback(LookupPriceInfo, nil);
  return nil;
}

+ (void)purchaseSucceeded:(NSDictionary*)payload onReply:(PurchaseEventReply)onReply {
  [ReportedPayloads addObject:payload];
  if (PurchaseReply != nil) onReply(PurchaseReply);
}
@end

// Stand-ins for the event post, the session wait and the request, so a purchase event can be
// run through TeakCore without a session or the network.
static TeakEvent* PostedEvent;
static TeakRequestResponse CapturedRequestCallback;

@interface TeakCoreTestDoubles : NSObject
@end

@implementation TeakCoreTestDoubles
+ (bool)postEvent:(TeakEvent*)event {
  PostedEvent = event;
  return true;
}

+ (void)whenUserIdIsReadyRun:(UserIdReadyBlock)block {
  block((TeakSession*)[NSNull null]);
}

+ (TeakRequest*)requestWithSession:(TeakSession*)session forEndpoint:(NSString*)endpoint withPayload:(NSDictionary*)payload method:(NSString*)method callback:(TeakRequestResponse)callback {
  CapturedRequestCallback = callback;
  return nil;
}
@end

static void SwapClassMethods(Class original, Class replacement, SEL selector) {
  method_exchangeImplementations(class_getClassMethod(original, selector), class_getClassMethod(replacement, selector));
}

static NSArray* PersistedTransactionIds(void) {
  return [[NSUserDefaults standardUserDefaults] arrayForKey:ReportedTransactionsDefaultsKey];
}

@implementation SKPaymentObserverTests

- (void)setUp {
  ClearClaimedTransactionIds();
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:ReportedTransactionsDefaultsKey];
}

- (void)tearDown {
  ClearClaimedTransactionIds();
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:ReportedTransactionsDefaultsKey];
}

// The StoreKit 1 observer seeing the sandbox purchase.
- (void)reportFromStoreKit1 {
  SKPayment* payment = mock([SKPayment class]);
  [given([payment productIdentifier]) willReturn:@"io.teak.app.unity.dev.dollar"];
  SKPaymentTransaction* transaction = mock([SKPaymentTransaction class]);
  [given([transaction payment]) willReturn:payment];
  [given([transaction transactionIdentifier]) willReturn:@"2000001265157858"];
  [given([transaction transactionDate]) willReturn:[NSDate date]];
  // Not init: that would register the observer for every event.
  [[SKPaymentObserver alloc] transactionPurchased:transaction];
}

- (void)withReportStandIns:(void (^)(void))block {
  ReportedPayloads = [NSMutableArray array];
  ProductLookups = 0;
  LookupCallsBack = YES;
  LookupPriceInfo = @{};
  PurchaseReply = nil;
  SwapClassMethods([ProductRequest class], [SKPaymentObserverTestDoubles class], @selector(productRequestForSku:callback:));
  SwapClassMethods([PurchaseEvent class], [SKPaymentObserverTestDoubles class], @selector(purchaseSucceeded:onReply:));
  block();
  SwapClassMethods([ProductRequest class], [SKPaymentObserverTestDoubles class], @selector(productRequestForSku:callback:));
  SwapClassMethods([PurchaseEvent class], [SKPaymentObserverTestDoubles class], @selector(purchaseSucceeded:onReply:));
}

#pragma mark - Reported transaction ids

- (void)testPersistedTransactionIdsAreBounded {
  for (int i = 0; i < 100; i++) {
    [SKPaymentObserver persistReportedTransactionId:[NSString stringWithFormat:@"%d", i]];
  }
  NSArray* persisted = PersistedTransactionIds();
  XCTAssertEqual(persisted.count, 64u);
  XCTAssertEqualObjects(persisted.lastObject, @"99");
  XCTAssertTrue([SKPaymentObserver claimTransactionId:@"0"], @"oldest ids age out");
}

#pragma mark - reportStoreKit2Transaction:

// The game reports a StoreKit 2 purchase once, and again later, and the StoreKit 1 observer
// also sees it: one send, priced from the JWS without a product lookup.
- (void)testReportedStoreKit2TransactionSendsOncePricedFromTheJWS {
  id<TeakStoreKit2Reporting> teak = BareTeak();
  NSString* jws = SandboxJWSWith(@{}, @[]);
  __block NSUInteger manualLookups = 0;
  [self withReportStandIns:^{
    [teak reportStoreKit2Transaction:jws];
    [teak reportStoreKit2Transaction:jws];
    manualLookups = ProductLookups;
    [self reportFromStoreKit1];
  }];

  XCTAssertEqual(ReportedPayloads.count, 1u);
  NSDictionary* payload = ReportedPayloads.firstObject;
  XCTAssertEqualObjects(payload[@"product_id"], @"io.teak.app.unity.dev.dollar");
  XCTAssertEqualObjects(payload[@"transaction_identifier"], @"2000001265157858");
  XCTAssertEqualObjects(payload[@"jws_representation"], jws);
  XCTAssertEqualObjects(payload[@"price_currency_code"], @"USD");
  XCTAssertEqualObjects(payload[@"price_float"], [NSDecimalNumber decimalNumberWithString:@"0.99"]);
  XCTAssertEqualObjects(payload[@"purchase_time"], @"2026-11-13T00:58:36+0000");
  XCTAssertEqual(manualLookups, 0u, @"the JWS price is what this transaction cost; no lookup");
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

#pragma mark - When a transaction counts as reported

// A successful reply marks the id reported, so it isn't sent again on a later launch.
- (void)testSuccessfulReplyMarksTheTransactionReported {
  id<TeakStoreKit2Reporting> teak = BareTeak();
  NSString* jws = SandboxJWSWith(@{}, @[]);
  [self withReportStandIns:^{
    PurchaseReply = @{@"code" : @200};
    [teak reportStoreKit2Transaction:jws];
    ClearClaimedTransactionIds();
    [teak reportStoreKit2Transaction:jws];
  }];
  XCTAssertEqual(ReportedPayloads.count, 1u);
  XCTAssertEqualObjects(PersistedTransactionIds(), @[ @"2000001265157858" ]);
}

// A failed send frees the id, so the next report of it is sent.
- (void)testFailedReplyLetsTheTransactionBeSentAgain {
  id<TeakStoreKit2Reporting> teak = BareTeak();
  NSString* jws = SandboxJWSWith(@{}, @[]);
  [self withReportStandIns:^{
    PurchaseReply = @{};
    [teak reportStoreKit2Transaction:jws];
    PurchaseReply = @{@"status" : @"invalid_user", @"code" : @404};
    [teak reportStoreKit2Transaction:jws];
    [teak reportStoreKit2Transaction:jws];
  }];
  XCTAssertEqual(ReportedPayloads.count, 3u);
  XCTAssertNil(PersistedTransactionIds());
}

// The server accepts a purchase without a price but doesn't track it, so a send without one
// mustn't mark the id reported: a later report with a price still goes out.
- (void)testStoreKit1SendWithoutAPriceDoesNotMarkTheTransactionReported {
  id<TeakStoreKit2Reporting> teak = BareTeak();
  [self withReportStandIns:^{
    PurchaseReply = @{@"code" : @200};
    [self reportFromStoreKit1];
    [teak reportStoreKit2Transaction:SandboxJWSWith(@{}, @[])];
  }];
  XCTAssertEqual(ReportedPayloads.count, 2u);
  XCTAssertNil(ReportedPayloads.firstObject[@"price_float"]);
  XCTAssertEqualObjects(ReportedPayloads.lastObject[@"price_currency_code"], @"USD");
  XCTAssertEqualObjects(PersistedTransactionIds(), @[ @"2000001265157858" ]);
}

// The StoreKit 1 observer doesn't remember ids across launches: Xcode's StoreKit Testing
// restarts them at 0 when the tester clears transactions.
- (void)testStoreKit1SendIsNotRememberedAcrossLaunches {
  [self withReportStandIns:^{
    PurchaseReply = @{@"code" : @200};
    LookupPriceInfo = @{@"price_currency_code" : @"USD", @"price_float" : @0.99};
    [self reportFromStoreKit1];
  }];
  XCTAssertEqual(ReportedPayloads.count, 1u);
  XCTAssertEqualObjects(ReportedPayloads.firstObject[@"price_currency_code"], @"USD");
  XCTAssertNil(PersistedTransactionIds());
}

// Nor are ids from a JWS made by Xcode's StoreKit Testing.
- (void)testXcodeTestingTransactionsAreNotMarkedReported {
  id<TeakStoreKit2Reporting> teak = BareTeak();
  [self withReportStandIns:^{
    PurchaseReply = @{@"code" : @200};
    [teak reportStoreKit2Transaction:SandboxJWSWith(@{@"environment" : @"Xcode", @"transactionId" : @"0"}, @[])];
  }];
  XCTAssertEqual(ReportedPayloads.count, 1u);
  XCTAssertNil(PersistedTransactionIds());
}

// A StoreKit 1 product lookup that never returns mustn't hold the transaction id.
- (void)testHungStoreKit1LookupDoesNotBlockTheGamesReport {
  id<TeakStoreKit2Reporting> teak = BareTeak();
  NSString* jws = SandboxJWSWith(@{}, @[]);
  [self withReportStandIns:^{
    LookupCallsBack = NO;
    [self reportFromStoreKit1];
    [teak reportStoreKit2Transaction:jws];
  }];
  XCTAssertEqual(ReportedPayloads.count, 1u);
  XCTAssertEqualObjects(ReportedPayloads.firstObject[@"jws_representation"], jws);
}

// The server's reply to /me/purchase reaches the reporter's onReply.
- (void)testPurchaseReplyReachesTheReporter {
  __block NSDictionary* received = nil;
  PostedEvent = nil;
  CapturedRequestCallback = nil;
  SEL post = @selector(postEvent:);
  SEL wait = @selector(whenUserIdIsReadyRun:);
  SEL request = @selector(requestWithSession:forEndpoint:withPayload:method:callback:);
  SwapClassMethods([TeakEvent class], [TeakCoreTestDoubles class], post);
  SwapClassMethods([TeakSession class], [TeakCoreTestDoubles class], wait);
  SwapClassMethods([TeakRequest class], [TeakCoreTestDoubles class], request);
  [PurchaseEvent purchaseSucceeded:@{@"product_id" : @"io.teak.app.unity.dev.dollar"}
                           onReply:^(NSDictionary* reply) {
                             received = reply;
                           }];
  if (PostedEvent != nil) {
    [[TeakCore alloc] handleEvent:PostedEvent]; // not init: that would register it for every event
  }
  SwapClassMethods([TeakEvent class], [TeakCoreTestDoubles class], post);
  SwapClassMethods([TeakSession class], [TeakCoreTestDoubles class], wait);
  SwapClassMethods([TeakRequest class], [TeakCoreTestDoubles class], request);

  XCTAssertNotNil(CapturedRequestCallback);
  if (CapturedRequestCallback != nil) CapturedRequestCallback(@{@"code" : @200});
  XCTAssertEqualObjects(received, @{@"code" : @200});
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
