#import <XCTest/XCTest.h>

#import "TeakLiveActivityTokenCache.h"

@interface TeakLiveActivityTokenCacheTests : XCTestCase
@property (nonatomic, strong) TeakLiveActivityTokenCache* cache;
@end

@implementation TeakLiveActivityTokenCacheTests

- (void)setUp {
  [super setUp];
  self.cache = [[TeakLiveActivityTokenCache alloc] init];
}

- (BOOL)claim:(NSString*)activityId signature:(NSString*)signature generation:(NSUInteger*)generation {
  return [self.cache claimActivityId:activityId signature:signature generation:generation];
}

- (BOOL)claim:(NSString*)activityId signature:(NSString*)signature {
  NSUInteger generation = 0;
  return [self claim:activityId signature:signature generation:&generation];
}

- (void)testReleaseOfSupersededSignatureKeepsTheNewerClaim {
  NSUInteger oldGeneration = 0;
  XCTAssertTrue([self claim:@"a" signature:@"t1|s1" generation:&oldGeneration]);
  XCTAssertTrue([self claim:@"a" signature:@"t2|s1"]);
  [self.cache releaseActivityId:@"a" signature:@"t1|s1" generation:oldGeneration];
  XCTAssertFalse([self claim:@"a" signature:@"t2|s1"]);
}

- (void)testReleaseFromBeforeResetCannotDropANewClaim {
  NSUInteger staleGeneration = 0;
  XCTAssertTrue([self claim:@"a" signature:@"t1|s1" generation:&staleGeneration]);
  [self.cache reset];
  XCTAssertTrue([self claim:@"a" signature:@"t1|s1"]);
  [self.cache releaseActivityId:@"a" signature:@"t1|s1" generation:staleGeneration];
  XCTAssertFalse([self claim:@"a" signature:@"t1|s1"]);
}

- (void)testConcurrentDuplicateClaimsSendExactlyOnce {
  __block int sent = 0;
  NSLock* lock = [[NSLock alloc] init];
  dispatch_apply(200, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t i) {
    NSUInteger generation = 0;
    if ([self.cache claimActivityId:@"a" signature:@"t1|s1" generation:&generation]) {
      [lock lock];
      sent++;
      [lock unlock];
    }
  });
  XCTAssertEqual(sent, 1);
}

@end
