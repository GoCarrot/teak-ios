#import "TeakStoreKit2Transaction.h"

@implementation TeakStoreKit2Transaction

+ (NSDictionary*)payloadFromJWS:(NSString*)jws {
  if (![jws isKindOfClass:[NSString class]]) return nil;
  NSArray<NSString*>* parts = [jws componentsSeparatedByString:@"."];
  if (parts.count != 3 || parts[1].length == 0) return nil;

  // base64url → base64: swap the alphabet back and restore the padding.
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

+ (NSString*)skipReasonForTransaction:(NSDictionary*)transaction {
  if ([TeakStoreKit2Transaction transactionIdForTransaction:transaction] == nil) return @"missing_transaction_id";
  if (![transaction[@"productId"] isKindOfClass:[NSString class]]) return @"missing_product_id";
  if (transaction[@"revocationDate"] != nil && transaction[@"revocationDate"] != [NSNull null]) return @"revoked";

  id reason = transaction[@"transactionReason"];
  if ([reason isKindOfClass:[NSString class]] && ![reason isEqualToString:@"PURCHASE"]) {
    return [NSString stringWithFormat:@"reason_%@", reason];
  }
  return nil;
}

+ (NSString*)transactionIdForTransaction:(NSDictionary*)transaction {
  id transactionId = transaction[@"transactionId"];
  if ([transactionId isKindOfClass:[NSString class]]) return [transactionId length] > 0 ? transactionId : nil;
  if ([transactionId isKindOfClass:[NSNumber class]]) return [NSString stringWithFormat:@"%llu", [transactionId unsignedLongLongValue]];
  return nil;
}

+ (NSDictionary*)priceForTransaction:(NSDictionary*)transaction {
  id currency = transaction[@"currency"];
  id price = transaction[@"price"];
  if (![currency isKindOfClass:[NSString class]] || ![price isKindOfClass:[NSNumber class]]) return nil;

  NSDecimalNumber* thousandths = [NSDecimalNumber decimalNumberWithDecimal:[price decimalValue]];
  return @{
    @"price_currency_code" : currency,
    @"price_float" : [thousandths decimalNumberByMultiplyingByPowerOf10:-3]
  };
}

+ (NSDate*)purchaseDateForTransaction:(NSDictionary*)transaction {
  id milliseconds = transaction[@"purchaseDate"];
  if (![milliseconds isKindOfClass:[NSNumber class]]) return nil;
  return [NSDate dateWithTimeIntervalSince1970:[milliseconds doubleValue] / 1000.0];
}

@end
