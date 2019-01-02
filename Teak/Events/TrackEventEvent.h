#import "TeakEvent.h"

@interface TrackEventEvent : TeakEvent
@property (strong, nonatomic, readonly) NSDictionary* _Nonnull payload;

+ (void)trackedEventWithPayload:(NSDictionary* _Nonnull)payload;
@end
