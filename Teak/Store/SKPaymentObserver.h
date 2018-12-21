#import <StoreKit/StoreKit.h>

typedef void (^ProductRequestCallback)(NSDictionary* _Nonnull, SKProductsResponse* _Nullable);

@interface SKPaymentObserver : NSObject
- (nonnull id)init;
@end

@interface ProductRequest : NSObject <SKProductsRequestDelegate>
+ (ProductRequest* _Nullable)productRequestForSku:(NSString* _Nonnull)sku callback:(ProductRequestCallback _Nonnull)callback;

- (void)productsRequest:(SKProductsRequest* _Nonnull)request didReceiveResponse:(SKProductsResponse* _Nonnull)response;
@end
