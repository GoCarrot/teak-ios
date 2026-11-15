#import <Foundation/Foundation.h>

// The transaction from a sandbox consumable bought with Unity IAP 5 on an iOS 18.7 device,
// with `changes` applied and the `removing` keys dropped.
static inline NSDictionary* SandboxTransactionWith(NSDictionary* changes, NSArray* removing) {
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
  return transaction;
}

// That transaction as the payload of a JWS with a placeholder header and signature. Only the
// payload segment is read.
static inline NSString* SandboxJWSWith(NSDictionary* changes, NSArray* removing) {
  NSData* json = [NSJSONSerialization dataWithJSONObject:SandboxTransactionWith(changes, removing) options:0 error:nil];
  NSString* payload = [json base64EncodedStringWithOptions:0];
  payload = [[[payload stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
      stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
      stringByReplacingOccurrencesOfString:@"=" withString:@""];
  return [NSString stringWithFormat:@"eyJhbGciOiJFUzI1NiJ9.%@.c2lnbmF0dXJl", payload];
}
