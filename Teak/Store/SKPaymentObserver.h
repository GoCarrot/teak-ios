#import <StoreKit/StoreKit.h>

typedef void (^ProductRequestCallback)(NSDictionary* _Nonnull, SKProductsResponse* _Nullable);

@interface SKPaymentObserver : NSObject
- (nonnull id)init;

// Reports a StoreKit 2 purchase from its JWS. Invalid JWSs, renewals, revoked transactions
// and Family Sharing copies are logged and not sent. The server dedupes by transaction id.
+ (void)reportStoreKit2TransactionJWS:(NSString* _Nullable)jwsRepresentation;
@end

@interface ProductRequest : NSObject <SKProductsRequestDelegate>
+ (ProductRequest* _Nullable)productRequestForSku:(NSString* _Nonnull)sku callback:(ProductRequestCallback _Nonnull)callback;

- (void)productsRequest:(SKProductsRequest* _Nonnull)request didReceiveResponse:(SKProductsResponse* _Nonnull)response;
@end
