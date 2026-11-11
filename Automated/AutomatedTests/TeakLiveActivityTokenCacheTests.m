#import <XCTest/XCTest.h>

#import "TeakLiveActivityTokenCache.h"
#import "TeakOperation.h"

@interface TeakLiveActivityTokenCacheTests : XCTestCase
@property (nonatomic, strong) TeakLiveActivityTokenCache* cache;
@end

@implementation TeakLiveActivityTokenCacheTests

- (void)setUp {
  [super setUp];
  self.cache = [[TeakLiveActivityTokenCache alloc] init];
}

- (TeakOperation*)operation {
  return [TeakOperation withResult:@"result"];
}

// Records `op` for `activityId`, returning whether it was recorded rather than a prior operation returned.
- (BOOL)record:(TeakOperation*)op activityId:(NSString*)activityId signature:(NSString*)signature {
  return [self.cache operationForActivityId:activityId signature:signature orRecord:op] == nil;
}

- (void)testReleaseOfSupersededOperationKeepsTheNewerEntry {
  TeakOperation* old = [self operation];
  TeakOperation* newer = [self operation];
  XCTAssertTrue([self record:old activityId:@"a" signature:@"t1|s1"]);
  XCTAssertTrue([self record:newer activityId:@"a" signature:@"t2|s1"]);

  [self.cache releaseOperation:old forActivityId:@"a"];

  XCTAssertEqual([self.cache operationForActivityId:@"a" signature:@"t2|s1" orRecord:[self operation]], newer);
}

- (void)testReleaseFromBeforeResetCannotDropANewEntry {
  TeakOperation* stale = [self operation];
  TeakOperation* fresh = [self operation];
  XCTAssertTrue([self record:stale activityId:@"a" signature:@"t1|s1"]);
  [self.cache reset];
  XCTAssertTrue([self record:fresh activityId:@"a" signature:@"t1|s1"]);

  [self.cache releaseOperation:stale forActivityId:@"a"];

  XCTAssertEqual([self.cache operationForActivityId:@"a" signature:@"t1|s1" orRecord:[self operation]], fresh);
}

- (void)testConcurrentDuplicatesRecordExactlyOneOperation {
  __block int recorded = 0;
  NSLock* lock = [[NSLock alloc] init];
  dispatch_apply(200, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t i) {
    TeakOperation* existing = [self.cache operationForActivityId:@"a" signature:@"t1|s1" orRecord:[self operation]];
    if (existing == nil) {
      [lock lock];
      recorded++;
      [lock unlock];
    }
  });
  XCTAssertEqual(recorded, 1);
}

@end
