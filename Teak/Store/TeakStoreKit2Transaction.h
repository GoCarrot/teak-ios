#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// A StoreKit 2 transaction read from its JWS. Plain Foundation, no StoreKit 2 API, so it
// works from Objective-C. The JWS signature is not verified here.
@interface TeakStoreKit2Transaction : NSObject

// nil unless the JWS decodes to a payload with a transactionId and productId.
- (nullable instancetype)initWithJWS:(nullable NSString*)jws;
- (instancetype)init NS_UNAVAILABLE;

@property (strong, nonatomic, readonly) NSString* jwsRepresentation;
@property (strong, nonatomic, readonly) NSString* transactionId;
@property (strong, nonatomic, readonly) NSString* productId;
@property (strong, nonatomic, readonly, nullable) NSDate* purchaseDate;

// In currency units; StoreKit 2 reports thousandths. Both nil unless the JWS has both.
@property (strong, nonatomic, readonly, nullable) NSDecimalNumber* price;
@property (strong, nonatomic, readonly, nullable) NSString* currency;

// nil when the transaction should be reported, otherwise a short reason for skipping it.
// A missing transactionReason is reported: it may be absent on older OS versions (the
// Swift Transaction.reason property is iOS 17+).
@property (strong, nonatomic, readonly, nullable) NSString* skipReason;

@end

NS_ASSUME_NONNULL_END
