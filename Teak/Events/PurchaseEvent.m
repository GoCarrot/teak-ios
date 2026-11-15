#import "PurchaseEvent.h"

@interface PurchaseEvent ()
@property (strong, nonatomic, readwrite) NSDictionary* _Nonnull payload;
@end

@implementation PurchaseEvent
+ (void)purchaseFailed:(NSDictionary* _Nonnull)payload {
  PurchaseEvent* event = [[PurchaseEvent alloc] initWithType:PurchaseFailed];
  event.payload = payload;
  [TeakEvent postEvent:event];
}

+ (void)purchaseSucceeded:(NSDictionary* _Nonnull)payload {
  PurchaseEvent* event = [[PurchaseEvent alloc] initWithType:PurchaseSucceeded];
  event.payload = payload;
  [TeakEvent postEvent:event];
}
@end
