#import <XCTest/XCTest.h>

#import "PushRegistrationEvent.h"
#import "TeakEvent.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Expose the internal serial event processing queue so tests can flush pending events.
@interface TeakEvent (Testing)
+ (dispatch_queue_t)eventProcessingQueue;
@end

@interface PushToStartTokenRegistrationTests : XCTestCase
@property (strong, nonatomic) NSMutableArray<PushRegistrationEvent*>* capturedEvents;
@property (strong, nonatomic) TeakEventBlockHandler* handler;
@end

@implementation PushToStartTokenRegistrationTests

- (void)setUp {
  self.capturedEvents = [[NSMutableArray alloc] init];
  NSMutableArray* events = self.capturedEvents;
  self.handler = [TeakEventBlockHandler handlerWithBlock:^(TeakEvent* event) {
    if (event.type == LiveActivityPushToStartRegistered) {
      @synchronized(events) {
        [events addObject:(PushRegistrationEvent*)event];
      }
    }
  }];
  [TeakEvent addEventHandler:self.handler];
}

- (void)tearDown {
  [TeakEvent removeEventHandler:self.handler];
  self.handler = nil;
  self.capturedEvents = nil;
}

- (NSData*)sampleTokenData {
  unsigned char bytes[] = {0xde, 0xad, 0xbe, 0xef, 0xca, 0xfe, 0x01, 0x23};
  return [NSData dataWithBytes:bytes length:sizeof(bytes)];
}

- (NSArray<PushRegistrationEvent*>*)drainCapturedEvents {
  // postEvent: dispatches onto a serial queue; a synchronous barrier guarantees that any
  // event posted before this call has been delivered to registered handlers.
  dispatch_sync([TeakEvent eventProcessingQueue], ^{
  });
  @synchronized(self.capturedEvents) {
    return [self.capturedEvents copy];
  }
}

#pragma mark - Input validation

- (void)testNilTokenDoesNotPostEvent {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
  [Teak registerPushToStartToken:nil];
#pragma clang diagnostic pop

  assertThat([self drainCapturedEvents], hasCountOf(0));
}

- (void)testEmptyTokenDoesNotPostEvent {
  [Teak registerPushToStartToken:[NSData data]];

  assertThat([self drainCapturedEvents], hasCountOf(0));
}

#pragma mark - Event posting

- (void)testValidTokenPostsEventWithLowercaseHexString {
  [Teak registerPushToStartToken:[self sampleTokenData]];

  NSArray<PushRegistrationEvent*>* events = [self drainCapturedEvents];
  assertThat(events, hasCountOf(1));
  assertThat(events[0].token, is(@"deadbeefcafe0123"));
}

- (void)testValidTokenEventUsesLiveActivityPushToStartRegisteredType {
  [Teak registerPushToStartToken:[self sampleTokenData]];

  NSArray<PushRegistrationEvent*>* events = [self drainCapturedEvents];
  assertThat(events, hasCountOf(1));
  XCTAssertEqual(events[0].type, LiveActivityPushToStartRegistered);
}

@end
