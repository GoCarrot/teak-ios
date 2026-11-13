#import "PurchaseEvent.h"

@interface PurchaseEvent ()
@property (strong, nonatomic, readwrite) NSDictionary* _Nonnull payload;
@property (copy, nonatomic, readwrite) PurchaseEventReply _Nullable onReply;
@end

@implementation PurchaseEvent
+ (void)purchaseFailed:(NSDictionary* _Nonnull)payload {
  PurchaseEvent* event = [[PurchaseEvent alloc] initWithType:PurchaseFailed];
  event.payload = payload;
  [TeakEvent postEvent:event];
}

+ (void)purchaseSucceeded:(NSDictionary* _Nonnull)payload {
  [PurchaseEvent purchaseSucceeded:payload onReply:nil];
}

+ (void)purchaseSucceeded:(NSDictionary* _Nonnull)payload onReply:(PurchaseEventReply _Nullable)onReply {
  PurchaseEvent* event = [[PurchaseEvent alloc] initWithType:PurchaseSucceeded];
  event.payload = payload;
  event.onReply = onReply;
  [TeakEvent postEvent:event];
}
@end
