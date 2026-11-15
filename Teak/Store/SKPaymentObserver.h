#import <StoreKit/StoreKit.h>

typedef void (^ProductRequestCallback)(NSDictionary* _Nonnull, SKProductsResponse* _Nullable);

@interface SKPaymentObserver : NSObject
- (nonnull id)init;

// Reports a purchase, once per transaction id across every path (the StoreKit 1 observer,
// the game's StoreKit 2 reports). With a price (price_currency_code, price_float) it sends
// that; without one it looks the product up. A successful, priced send marks the id reported
// for this launch, and for later launches if rememberAcrossLaunches. Never finishes the
// transaction.
+ (void)reportPurchaseOfProduct:(NSString* _Nonnull)productId
                  transactionId:(NSString* _Nullable)transactionId
                   purchaseDate:(NSDate* _Nullable)purchaseDate
               purchaseDuration:(NSNumber* _Nullable)purchaseDuration
                         source:(NSString* _Nonnull)source
                          price:(NSDictionary* _Nullable)price
                       jwsToken:(NSString* _Nullable)jwsToken
         rememberAcrossLaunches:(BOOL)rememberAcrossLaunches;

// Reports a StoreKit 2 purchase from its JWS. Invalid JWSs, renewals, revoked transactions
// and Family Sharing copies are logged and not sent.
+ (void)reportStoreKit2TransactionJWS:(NSString* _Nullable)jwsRepresentation;
@end

@interface ProductRequest : NSObject <SKProductsRequestDelegate>
+ (ProductRequest* _Nullable)productRequestForSku:(NSString* _Nonnull)sku callback:(ProductRequestCallback _Nonnull)callback;

- (void)productsRequest:(SKProductsRequest* _Nonnull)request didReceiveResponse:(SKProductsResponse* _Nonnull)response;
@end
