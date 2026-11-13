#import <XCTest/XCTest.h>

#import "TeakStoreKit2Transaction.h"

// A real StoreKit 2 transaction JSON, captured from a sandbox consumable purchase made by
// Unity IAP 5 on an iOS 18.7 device.
static NSString* const SandboxTransactionJSON = @"{\"transactionId\":\"2000001265157858\",\"originalTransactionId\":\"2000001265157858\",\"bundleId\":\"io.teak.app.unity.dev\",\"productId\":\"io.teak.app.unity.dev.dollar\",\"purchaseDate\":1794531516000,\"originalPurchaseDate\":1794531516000,\"quantity\":1,\"type\":\"Consumable\",\"deviceVerification\":\"uP3H3e92tXvX9Pkh2Hpc7V04K8/UpZUFS108XkA1tXkqka3Xkyz7rQUWRnHZYUtt\",\"deviceVerificationNonce\":\"56387876-d455-4280-93ff-99cd35afeb08\",\"appAccountToken\":\"00000000-0000-0000-0000-000000000000\",\"inAppOwnershipType\":\"PURCHASED\",\"signedDate\":1794531517446,\"environment\":\"Sandbox\",\"transactionReason\":\"PURCHASE\",\"storefront\":\"USA\",\"storefrontId\":\"143441\",\"price\":990,\"currency\":\"USD\",\"appTransactionId\":\"706051954853445094\"}";

// The same JSON as a JWS payload (base64url, no padding) with a placeholder header and
// signature. Decoding doesn't verify the signature, so only the payload segment matters.
static NSString* const SandboxTransactionJWS = @"eyJhbGciOiJFUzI1NiJ9.eyJ0cmFuc2FjdGlvbklkIjoiMjAwMDAwMTI2NTE1Nzg1OCIsIm9yaWdpbmFsVHJhbnNhY3Rpb25JZCI6IjIwMDAwMDEyNjUxNTc4NTgiLCJidW5kbGVJZCI6ImlvLnRlYWsuYXBwLnVuaXR5LmRldiIsInByb2R1Y3RJZCI6ImlvLnRlYWsuYXBwLnVuaXR5LmRldi5kb2xsYXIiLCJwdXJjaGFzZURhdGUiOjE3OTQ1MzE1MTYwMDAsIm9yaWdpbmFsUHVyY2hhc2VEYXRlIjoxNzk0NTMxNTE2MDAwLCJxdWFudGl0eSI6MSwidHlwZSI6IkNvbnN1bWFibGUiLCJkZXZpY2VWZXJpZmljYXRpb24iOiJ1UDNIM2U5MnRYdlg5UGtoMkhwYzdWMDRLOC9VcFpVRlMxMDhYa0ExdFhrcWthM1hreXo3clFVV1JuSFpZVXR0IiwiZGV2aWNlVmVyaWZpY2F0aW9uTm9uY2UiOiI1NjM4Nzg3Ni1kNDU1LTQyODAtOTNmZi05OWNkMzVhZmViMDgiLCJhcHBBY2NvdW50VG9rZW4iOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDAiLCJpbkFwcE93bmVyc2hpcFR5cGUiOiJQVVJDSEFTRUQiLCJzaWduZWREYXRlIjoxNzk0NTMxNTE3NDQ2LCJlbnZpcm9ubWVudCI6IlNhbmRib3giLCJ0cmFuc2FjdGlvblJlYXNvbiI6IlBVUkNIQVNFIiwic3RvcmVmcm9udCI6IlVTQSIsInN0b3JlZnJvbnRJZCI6IjE0MzQ0MSIsInByaWNlIjo5OTAsImN1cnJlbmN5IjoiVVNEIiwiYXBwVHJhbnNhY3Rpb25JZCI6IjcwNjA1MTk1NDg1MzQ0NTA5NCJ9.c2lnbmF0dXJl";

@interface TeakStoreKit2TransactionTests : XCTestCase
@end

@implementation TeakStoreKit2TransactionTests

- (NSDictionary*)sandboxTransaction {
  return [NSJSONSerialization JSONObjectWithData:[SandboxTransactionJSON dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
}

- (NSDictionary*)sandboxTransactionWith:(NSDictionary*)changes removing:(NSArray*)keys {
  NSMutableDictionary* transaction = [[self sandboxTransaction] mutableCopy];
  [transaction addEntriesFromDictionary:changes];
  [transaction removeObjectsForKeys:keys];
  return transaction;
}

#pragma mark - JWS payload

- (void)testJWSPayloadDecodesToTheTransaction {
  NSDictionary* payload = [TeakStoreKit2Transaction payloadFromJWS:SandboxTransactionJWS];
  XCTAssertEqualObjects(payload, [self sandboxTransaction]);
}

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

#pragma mark - Report or skip

- (void)testSandboxPurchaseIsReported {
  XCTAssertNil([TeakStoreKit2Transaction skipReasonForTransaction:[self sandboxTransaction]]);
}

- (void)testNonPurchaseReasonIsSkipped {
  NSDictionary* renewal = [self sandboxTransactionWith:@{@"transactionReason" : @"RENEWAL"} removing:@[]];
  XCTAssertEqualObjects([TeakStoreKit2Transaction skipReasonForTransaction:renewal], @"reason_RENEWAL");
}

// Transaction.reason is iOS 17+; on older OS versions the key may be absent, and those
// purchases must still be reported.
- (void)testMissingReasonIsReported {
  NSDictionary* noReason = [self sandboxTransactionWith:@{} removing:@[ @"transactionReason" ]];
  XCTAssertNil([TeakStoreKit2Transaction skipReasonForTransaction:noReason]);
}

- (void)testRevokedTransactionIsSkipped {
  NSDictionary* revoked = [self sandboxTransactionWith:@{@"revocationDate" : @1794531600000} removing:@[]];
  XCTAssertEqualObjects([TeakStoreKit2Transaction skipReasonForTransaction:revoked], @"revoked");
}

- (void)testTransactionWithoutIdsIsSkipped {
  NSDictionary* noProduct = [self sandboxTransactionWith:@{} removing:@[ @"productId" ]];
  NSDictionary* noTransaction = [self sandboxTransactionWith:@{} removing:@[ @"transactionId" ]];
  XCTAssertEqualObjects([TeakStoreKit2Transaction skipReasonForTransaction:noProduct], @"missing_product_id");
  XCTAssertEqualObjects([TeakStoreKit2Transaction skipReasonForTransaction:noTransaction], @"missing_transaction_id");
}

#pragma mark - Payload fields

// StoreKit 2 reports price in thousandths of the currency unit: 990 is 0.99.
- (void)testPriceIsConvertedFromThousandths {
  NSDictionary* price = [TeakStoreKit2Transaction priceForTransaction:[self sandboxTransaction]];
  XCTAssertEqualObjects(price[@"price_currency_code"], @"USD");
  XCTAssertEqualObjects(price[@"price_float"], [NSDecimalNumber decimalNumberWithString:@"0.99"]);
}

- (void)testPriceWithoutCurrencyOrAmountIsNil {
  XCTAssertNil([TeakStoreKit2Transaction priceForTransaction:[self sandboxTransactionWith:@{} removing:@[ @"currency" ]]]);
  XCTAssertNil([TeakStoreKit2Transaction priceForTransaction:[self sandboxTransactionWith:@{} removing:@[ @"price" ]]]);
}

- (void)testPurchaseDateIsConvertedFromMilliseconds {
  NSDate* date = [TeakStoreKit2Transaction purchaseDateForTransaction:[self sandboxTransaction]];
  XCTAssertEqualWithAccuracy(date.timeIntervalSince1970, 1794531516.0, 0.001);
  XCTAssertNil([TeakStoreKit2Transaction purchaseDateForTransaction:[self sandboxTransactionWith:@{} removing:@[ @"purchaseDate" ]]]);
}

// The SK1 observer's transactionIdentifier is the same decimal string, which is what lets
// the StoreKit 1 and StoreKit 2 paths dedupe against each other.
- (void)testTransactionIdIsADecimalString {
  XCTAssertEqualObjects([TeakStoreKit2Transaction transactionIdForTransaction:[self sandboxTransaction]], @"2000001265157858");
  XCTAssertEqualObjects([TeakStoreKit2Transaction transactionIdForTransaction:@{@"transactionId" : @2000001265157858}], @"2000001265157858");
  XCTAssertNil([TeakStoreKit2Transaction transactionIdForTransaction:@{}]);
}

@end
