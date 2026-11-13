#import <StoreKit/StoreKit.h>

typedef void (^ProductRequestCallback)(NSDictionary* _Nonnull, SKProductsResponse* _Nullable);

@interface SKPaymentObserver : NSObject
- (nonnull id)init;

// Reports a purchase that the StoreKit 1 observer can't see (e.g. a StoreKit 2
// purchase made by another library). Deduplicated by transaction id against
// the observer path. Never finishes the transaction.
+ (void)reportPurchaseOfProduct:(NSString* _Nonnull)productId
                  transactionId:(NSString* _Nullable)transactionId
                   purchaseDate:(NSDate* _Nullable)purchaseDate
               purchaseDuration:(NSNumber* _Nullable)purchaseDuration
                         source:(NSString* _Nonnull)source
                  fallbackPrice:(NSDictionary* _Nullable)fallbackPrice
                       jwsToken:(NSString* _Nullable)jwsToken;
@end

@interface ProductRequest : NSObject <SKProductsRequestDelegate>
+ (ProductRequest* _Nullable)productRequestForSku:(NSString* _Nonnull)sku callback:(ProductRequestCallback _Nonnull)callback;

- (void)productsRequest:(SKProductsRequest* _Nonnull)request didReceiveResponse:(SKProductsResponse* _Nonnull)response;
@end
