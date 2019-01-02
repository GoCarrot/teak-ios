#import "TeakEvent.h"

@interface PurchaseEvent : TeakEvent
@property (strong, nonatomic, readonly) NSDictionary* _Nonnull payload;

+ (void)purchaseFailed:(NSDictionary* _Nonnull)payload;
+ (void)purchaseSucceeded:(NSDictionary* _Nonnull)payload;
@end
