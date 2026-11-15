#import "TeakStoreKit2Transaction.h"

static NSDictionary* PayloadFromJWS(NSString* jws) {
  if (![jws isKindOfClass:[NSString class]]) return nil;
  NSArray<NSString*>* parts = [jws componentsSeparatedByString:@"."];
  if (parts.count != 3 || parts[1].length == 0) return nil;

  // base64url → base64.
  NSMutableString* base64 = [[parts[1] stringByReplacingOccurrencesOfString:@"-" withString:@"+"] mutableCopy];
  [base64 replaceOccurrencesOfString:@"_" withString:@"/" options:0 range:NSMakeRange(0, base64.length)];
  while (base64.length % 4 != 0) {
    [base64 appendString:@"="];
  }

  NSData* data = [[NSData alloc] initWithBase64EncodedString:base64 options:0];
  if (data == nil) return nil;
  id payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  return [payload isKindOfClass:[NSDictionary class]] ? payload : nil;
}

// The payload is untrusted JSON, so every field is type-checked as it's read.
static id ValueOfClass(NSDictionary* payload, NSString* key, Class cls) {
  id value = payload[key];
  return [value isKindOfClass:cls] ? value : nil;
}

@implementation TeakStoreKit2Transaction

- (instancetype)initWithJWS:(NSString*)jws {
  NSDictionary* payload = PayloadFromJWS(jws);
  NSString* transactionId = ValueOfClass(payload, @"transactionId", [NSString class]);
  NSString* productId = ValueOfClass(payload, @"productId", [NSString class]);
  if (transactionId.length == 0 || productId.length == 0) return nil;

  self = [super init];
  if (self) {
    _jwsRepresentation = jws;
    _transactionId = transactionId;
    _productId = productId;

    NSNumber* purchaseDate = ValueOfClass(payload, @"purchaseDate", [NSNumber class]);
    _purchaseDate = purchaseDate == nil ? nil : [NSDate dateWithTimeIntervalSince1970:purchaseDate.doubleValue / 1000.0];

    NSNumber* price = ValueOfClass(payload, @"price", [NSNumber class]);
    NSString* currency = ValueOfClass(payload, @"currency", [NSString class]);
    if (price != nil && currency != nil) {
      _price = [[NSDecimalNumber decimalNumberWithDecimal:price.decimalValue] decimalNumberByMultiplyingByPowerOf10:-3];
      _currency = currency;
    }

    NSString* reason = ValueOfClass(payload, @"transactionReason", [NSString class]);
    NSString* ownership = ValueOfClass(payload, @"inAppOwnershipType", [NSString class]);
    if (ValueOfClass(payload, @"revocationDate", [NSNumber class]) != nil) {
      _skipReason = @"revoked";
    } else if ([ownership isEqualToString:@"FAMILY_SHARED"]) {
      _skipReason = @"family_shared";
    } else if (reason != nil && ![reason isEqualToString:@"PURCHASE"]) {
      _skipReason = [NSString stringWithFormat:@"reason_%@", reason];
    }
  }
  return self;
}

@end
