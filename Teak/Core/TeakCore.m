#import "TeakCore.h"
#import "AdditionalDataEvent.h"
#import "PurchaseEvent.h"
#import "TeakRequest.h"
#import "TeakSession.h"
#import "TrackEventEvent.h"
#import "UserDataEvent.h"
#import <Teak/Teak.h>

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
                                                        method:TeakRequest_POST
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
                                                        method:TeakRequest_POST
                                                      callback:nil];
        [request send];
      }];
    } break;

    case AdditionalData: {
      [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
        [[NSNotificationCenter defaultCenter] postNotificationName:TeakAdditionalData
                                                            object:self
                                                          userInfo:((AdditionalDataEvent*)event).additionalData];
      }];
    } break;

    case UserData: {
      [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
        [[NSNotificationCenter defaultCenter] postNotificationName:TeakUserData
                                                            object:self
                                                          userInfo:[((UserDataEvent*)event) toDictionary]];
      }];
    } break;

    default:
      break;
  }
}

@end
