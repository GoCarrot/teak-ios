#import <XCTest/XCTest.h>

#import "TeakStoreKit2Fixtures.h"
#import "TeakStoreKit2Transaction.h"

@interface TeakStoreKit2TransactionTests : XCTestCase
@end

@implementation TeakStoreKit2TransactionTests

static TeakStoreKit2Transaction* TransactionWith(NSDictionary* changes, NSArray* removing) {
  return [[TeakStoreKit2Transaction alloc] initWithJWS:SandboxJWSWith(changes, removing)];
}

- (void)testSandboxTransactionReadsEveryField {
  NSString* jws = SandboxJWSWith(@{}, @[]);
  TeakStoreKit2Transaction* transaction = [[TeakStoreKit2Transaction alloc] initWithJWS:jws];
  XCTAssertEqualObjects(transaction.jwsRepresentation, jws);
  XCTAssertEqualObjects(transaction.transactionId, @"2000001265157858");
  XCTAssertEqualObjects(transaction.productId, @"io.teak.app.unity.dev.dollar");
  XCTAssertEqualObjects(transaction.price, [NSDecimalNumber decimalNumberWithString:@"0.99"]);
  XCTAssertEqualObjects(transaction.currency, @"USD");
  XCTAssertEqualObjects(transaction.purchaseDate, [NSDate dateWithTimeIntervalSince1970:1794531516]);
  XCTAssertTrue(transaction.hasTransactionReason);
  XCTAssertNil(transaction.skipReason);
}

// base64url drops padding and uses '-' and '_'; NSData's decoder needs both undone.
- (void)testJWSPayloadNeedingPaddingAndURLSafeCharactersDecodes {
  NSString* jws = @"eyJhbGciOiJFUzI1NiJ9.eyJ0cmFuc2FjdGlvbklkIjoiMTIiLCJwcm9kdWN0SWQiOiJhPz8-fngifQ.c2ln";
  TeakStoreKit2Transaction* transaction = [[TeakStoreKit2Transaction alloc] initWithJWS:jws];
  XCTAssertEqualObjects(transaction.transactionId, @"12");
  XCTAssertEqualObjects(transaction.productId, @"a??>~x");
}

- (void)testMalformedJWSIsNil {
  XCTAssertNil([[TeakStoreKit2Transaction alloc] initWithJWS:nil]);
  XCTAssertNil([[TeakStoreKit2Transaction alloc] initWithJWS:@""]);
  XCTAssertNil([[TeakStoreKit2Transaction alloc] initWithJWS:@"not-a-jws"]);
  XCTAssertNil([[TeakStoreKit2Transaction alloc] initWithJWS:@"a.b"], @"two segments");
  XCTAssertNil([[TeakStoreKit2Transaction alloc] initWithJWS:@"a.!!!.c"], @"payload isn't base64url");
  XCTAssertNil([[TeakStoreKit2Transaction alloc] initWithJWS:@"a.bm90IGpzb24.c"], @"payload isn't JSON");
  XCTAssertNil([[TeakStoreKit2Transaction alloc] initWithJWS:@"a.WzFd.c"], @"payload is a JSON array, not an object");
}

- (void)testTransactionWithoutIdsIsNil {
  XCTAssertNil(TransactionWith(@{}, @[ @"productId" ]));
  XCTAssertNil(TransactionWith(@{}, @[ @"transactionId" ]));
  XCTAssertNil(TransactionWith(@{@"transactionId" : @2000001265157858}, @[]), @"a numeric id isn't read as a string");
}

- (void)testPriceWithoutCurrencyOrAmountIsNil {
  TeakStoreKit2Transaction* noCurrency = TransactionWith(@{}, @[ @"currency" ]);
  TeakStoreKit2Transaction* noAmount = TransactionWith(@{}, @[ @"price" ]);
  XCTAssertNil(noCurrency.price);
  XCTAssertNil(noCurrency.currency);
  XCTAssertNil(noAmount.price);
  XCTAssertNil(noAmount.currency);
}

- (void)testSkipReasons {
  XCTAssertEqualObjects(TransactionWith(@{@"transactionReason" : @"RENEWAL"}, @[]).skipReason, @"reason_RENEWAL");
  XCTAssertEqualObjects(TransactionWith(@{@"revocationDate" : @1794531600000}, @[]).skipReason, @"revoked");
  XCTAssertEqualObjects(TransactionWith(@{@"inAppOwnershipType" : @"FAMILY_SHARED"}, @[]).skipReason, @"family_shared");
  XCTAssertNil(TransactionWith(@{@"revocationDate" : [NSNull null]}, @[]).skipReason);

  TeakStoreKit2Transaction* noReason = TransactionWith(@{}, @[ @"transactionReason" ]);
  XCTAssertNil(noReason.skipReason);
  XCTAssertFalse(noReason.hasTransactionReason);
}

@end
