#import "TeakEvent.h"

typedef void (^PurchaseEventReply)(NSDictionary* _Nonnull reply);

@interface PurchaseEvent : TeakEvent
@property (strong, nonatomic, readonly) NSDictionary* _Nonnull payload;
@property (copy, nonatomic, readonly) PurchaseEventReply _Nullable onReply;

+ (void)purchaseFailed:(NSDictionary* _Nonnull)payload;
+ (void)purchaseSucceeded:(NSDictionary* _Nonnull)payload;
+ (void)purchaseSucceeded:(NSDictionary* _Nonnull)payload onReply:(PurchaseEventReply _Nullable)onReply;
@end
