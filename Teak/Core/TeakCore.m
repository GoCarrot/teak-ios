#import "TeakCore.h"
#import "PurchaseEvent.h"
#import "TeakRequest.h"
#import "TeakSession.h"
#import "TrackEventEvent.h"

@implementation TeakCore

- (id)init {
  self = [super init];
  if (self) {
    [TeakEvent addEventHandler:self];

    // TODO: Would be great to have a better way of doing this
    [TeakSession registerStaticEventListeners];
  }
  return self;
}

- (void)dealloc {
  [TeakEvent removeEventHandler:self];
}

- (void)handleEvent:(TeakEvent* _Nonnull)event {
  switch (event.type) {
    case TrackedEvent: {
      [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
        TeakRequest* request = [TeakRequest requestWithSession:session
                                                   forEndpoint:@"/me/events"
                                                   withPayload:((TrackEventEvent*)event).payload
                                                      callback:nil];
        [request send];
      }];
    } break;

    // Same code handles both events, but keep two events just for code intent clarity
    case PurchaseFailed:
    case PurchaseSucceeded: {
      [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
        TeakRequest* request = [TeakRequest requestWithSession:session
                                                   forEndpoint:@"/me/purchase"
                                                   withPayload:((PurchaseEvent*)event).payload
                                                      callback:nil];
        [request send];
      }];
    } break;
    default:
      break;
  }
}

@end
