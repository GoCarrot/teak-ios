#import <XCTest/XCTest.h>

#import "TeakStoreKit2Fixtures.h"
#import "TeakStoreKit2Transaction.h"

@interface TeakStoreKit2TransactionTests : XCTestCase
@end

@implementation TeakStoreKit2TransactionTests

// base64url drops padding and uses '-' and '_'; NSData's decoder needs both undone.
- (void)testJWSPayloadNeedingPaddingAndURLSafeCharactersDecodes {
  NSString* jws = @"eyJhbGciOiJFUzI1NiJ9.eyJ0cmFuc2FjdGlvbklkIjoiMTIiLCJwcm9kdWN0SWQiOiJhPz8-fngifQ.c2ln";
  NSDictionary* payload = [TeakStoreKit2Transaction payloadFromJWS:jws];
  XCTAssertEqualObjects(payload[@"transactionId"], @"12");
  XCTAssertEqualObjects(payload[@"productId"], @"a??>~x");
}

- (void)testMalformedJWSDecodesToNil {
  XCTAssertNil([TeakStoreKit2Transaction payloadFromJWS:nil]);
  XCTAssertNil([TeakStoreKit2Transaction payloadFromJWS:@""]);
  XCTAssertNil([TeakStoreKit2Transaction payloadFromJWS:@"not-a-jws"]);
  XCTAssertNil([TeakStoreKit2Transaction payloadFromJWS:@"a.b"], @"two segments");
  XCTAssertNil([TeakStoreKit2Transaction payloadFromJWS:@"a.!!!.c"], @"payload isn't base64url");
  XCTAssertNil([TeakStoreKit2Transaction payloadFromJWS:@"a.bm90IGpzb24.c"], @"payload isn't JSON");
  XCTAssertNil([TeakStoreKit2Transaction payloadFromJWS:@"a.WzFd.c"], @"payload is a JSON array, not an object");
}

- (void)testTransactionWithoutIdsIsSkipped {
  NSDictionary* noProduct = SandboxTransactionWith(@{}, @[ @"productId" ]);
  NSDictionary* noTransaction = SandboxTransactionWith(@{}, @[ @"transactionId" ]);
  XCTAssertEqualObjects([TeakStoreKit2Transaction skipReasonForTransaction:noProduct], @"missing_product_id");
  XCTAssertEqualObjects([TeakStoreKit2Transaction skipReasonForTransaction:noTransaction], @"missing_transaction_id");
}

- (void)testPriceWithoutCurrencyOrAmountIsNil {
  XCTAssertNil([TeakStoreKit2Transaction priceForTransaction:SandboxTransactionWith(@{}, @[ @"currency" ])]);
  XCTAssertNil([TeakStoreKit2Transaction priceForTransaction:SandboxTransactionWith(@{}, @[ @"price" ])]);
}

@end
