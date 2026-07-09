#import <XCTest/XCTest.h>

#import "TeakUserProfile.h"
#import <Teak/Teak.h>

// setAttribute:forKey:inDictionary: must touch the attribute dictionary + firstSetTime
// only on the serial operationQueue. The pre-fix code read the dict and stamped
// firstSetTime synchronously on the caller's default-qos queue while the write ran on
// the serial queue — a concurrent read/write of the NSMutableDictionary (use-after-free).
//
// A behavioral race repro isn't feasible without ThreadSanitizer, so — following
// TeakSessionDeferredCallbackTests — these tests document the invariant instead: block
// the serial queue, invoke the real setter, and assert firstSetTime hasn't been stamped
// yet. The fixed code defers the stamp behind the gate (nil); the pre-fix code stamps it
// synchronously on the caller's queue, so this fails deterministically when reverted.
@interface Teak (Testing)
+ (dispatch_queue_t)operationQueue;
@end

@interface TeakUserProfile (Testing)
@property (strong, nonatomic) NSMutableDictionary* stringAttributes;
@property (strong, nonatomic) NSMutableDictionary* numberAttributes;
@property (strong, nonatomic) NSDate* firstSetTime;
@end

@interface TeakUserProfileAttributeQueueTests : XCTestCase
@end

@implementation TeakUserProfileAttributeQueueTests

// Occupies the serial operationQueue with a semaphore-gated block, invokes the setter,
// and asserts firstSetTime is still nil — proving the stamp (and the guard-read above it)
// were deferred onto the serial queue rather than run synchronously on the caller. Then
// releases the gate, drains the queue, and confirms the deferred stamp actually lands.
// The setter re-sets the existing value so safeNotEquals is false and no send is scheduled.
- (void)assertFirstSetTimeDeferredForProfile:(TeakUserProfile*)profile setter:(void (^)(void))invokeSetter {
  dispatch_semaphore_t gate = dispatch_semaphore_create(0);
  dispatch_async([Teak operationQueue], ^{
    dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER);
  });

  invokeSetter();

  XCTAssertNil(profile.firstSetTime,
               @"firstSetTime must be stamped on the serial operationQueue, not synchronously on the caller's queue");

  dispatch_semaphore_signal(gate);
  dispatch_sync([Teak operationQueue], ^{
  });

  XCTAssertNotNil(profile.firstSetTime,
                  @"firstSetTime should be stamped once the queued block runs");
}

- (void)testStringAttributeDefersDictAccessToSerialQueue {
  TeakUserProfile* profile = [[TeakUserProfile alloc] init];
  profile.stringAttributes = [@{@"key" : @"value"} mutableCopy];

  [self assertFirstSetTimeDeferredForProfile:profile
                                      setter:^{
                                        [profile setStringAttribute:@"value" forKey:@"key"];
                                      }];
}

- (void)testNumericAttributeDefersDictAccessToSerialQueue {
  TeakUserProfile* profile = [[TeakUserProfile alloc] init];
  profile.numberAttributes = [@{@"key" : [NSNumber numberWithDouble:1.0]} mutableCopy];

  [self assertFirstSetTimeDeferredForProfile:profile
                                      setter:^{
                                        [profile setNumericAttribute:1.0 forKey:@"key"];
                                      }];
}

@end
