#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Reads the fields Teak reports from a StoreKit 2 transaction, given either the
// transaction's JSON representation or its JWS. Plain Foundation, no StoreKit 2 API, so it
// works from Objective-C. The JWS signature is not verified here.
@interface TeakStoreKit2Transaction : NSObject

// The decoded payload segment of a JWS, or nil if it isn't a three-part JWS with a JSON
// object payload.
+ (nullable NSDictionary*)payloadFromJWS:(nullable NSString*)jws;

// nil when the transaction should be reported, otherwise a short reason for skipping it.
// A missing transactionReason is reported: it may be absent on older OS versions (the
// Swift Transaction.reason property is iOS 17+).
+ (nullable NSString*)skipReasonForTransaction:(NSDictionary*)transaction;

// The transaction id as a decimal string, matching SKPaymentTransaction.transactionIdentifier.
+ (nullable NSString*)transactionIdForTransaction:(NSDictionary*)transaction;

// price_currency_code and price_float for /me/purchase. StoreKit 2 reports price in
// thousandths of the currency unit.
+ (nullable NSDictionary*)priceForTransaction:(NSDictionary*)transaction;

+ (nullable NSDate*)purchaseDateForTransaction:(NSDictionary*)transaction;

@end

NS_ASSUME_NONNULL_END
