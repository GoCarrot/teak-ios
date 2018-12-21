#import "TrackEventEvent.h"

@interface TrackEventEvent ()
@property (strong, nonatomic, readwrite) NSDictionary* _Nonnull payload;
@end

@implementation TrackEventEvent

+ (void)trackedEventWithPayload:(NSDictionary* _Nonnull)payload {
  TrackEventEvent* event = [[TrackEventEvent alloc] initWithType:TrackedEvent];
  event.payload = payload;
  [TeakEvent postEvent:event];
}
@end
