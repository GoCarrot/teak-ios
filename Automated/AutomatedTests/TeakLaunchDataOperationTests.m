#import <XCTest/XCTest.h>

#import <Teak/Teak.h>

#import "TeakLaunchData.h"

// Forward-declare TeakConfiguration's init selector so +setUp can seed the
// singleton without importing TeakConfiguration.h (its transitive imports
// aren't on the test target's HEADER_SEARCH_PATHS and collide with Teak.h).
@interface TeakConfiguration : NSObject
+ (BOOL)configureForAppId:(NSString*)appId andSecret:(NSString*)appSecret;
@end

// Each launch-data operation must deallocate once nothing outside it holds a
// reference: an operation that owns a strong path back to itself never frees, and
// every launch leaks one.
@interface TeakLaunchDataOperationTests : XCTestCase
@end

@implementation TeakLaunchDataOperationTests

+ (void)setUp {
  [super setUp];
  // Launch-data classification reads TeakConfiguration.configuration.
  @try {
    [TeakConfiguration configureForAppId:@"test-app" andSecret:@"test-secret"];
  } @catch (NSException* e) {
    // Already initialized — fine.
  }
}

// Builds an operation inside its own autorelease pool, optionally runs it, and
// returns only a weak reference so the caller can check it freed.
- (void)assertOperationDeallocates:(TeakLaunchDataOperation* (^)(void))make run:(BOOL)run {
  __weak TeakLaunchDataOperation* weakOp = nil;
  @autoreleasepool {
    TeakLaunchDataOperation* op = make();
    XCTAssertNotNil(op);
    if (run) {
      [op start];
      XCTAssertTrue(op.isFinished);
    }
    weakOp = op;
  }
  XCTAssertNil(weakOp, @"TeakLaunchDataOperation was never deallocated");
}

- (void)testUnattributedDeallocates {
  [self assertOperationDeallocates:^{ return [TeakLaunchDataOperation unattributed]; } run:YES];
  [self assertOperationDeallocates:^{ return [TeakLaunchDataOperation unattributed]; } run:NO];
}

- (void)testFromOpenUrlDeallocates {
  NSURL* url = [NSURL URLWithString:@"teaktest-app://store/coins?teak_notif_id=12345"];
  [self assertOperationDeallocates:^{ return [TeakLaunchDataOperation fromOpenUrl:url]; } run:YES];
}

- (void)testFromLiveActivityTapDeallocates {
  [self assertOperationDeallocates:^{ return [TeakLaunchDataOperation fromLiveActivityTap:@"D3CBB9AF-7292-4FD9-B22D-DEAC3D033BD2"]; } run:YES];
}

// Not run: running resolves the link over the network. The leak this guards
// against formed at construction, so construction alone is the check.
- (void)testFromUniversalLinkDeallocates {
  NSURL* url = [NSURL URLWithString:@"https://teak.io/link/abc123"];
  [self assertOperationDeallocates:^{ return [TeakLaunchDataOperation fromUniversalLink:url]; } run:NO];
}

// updateDeepLink:withLaunchLink: replaces a session's operation; both the
// replaced operation and its replacement must free.
- (void)testUpdateDeepLinkDeallocates {
  __weak TeakLaunchDataOperation* weakOriginal = nil;
  __weak TeakLaunchDataOperation* weakUpdated = nil;
  @autoreleasepool {
    TeakLaunchDataOperation* original = [TeakLaunchDataOperation unattributed];
    [original start];
    TeakLaunchDataOperation* updated = [original updateDeepLink:[NSURL URLWithString:@"teaktest-app://store/coins"]
                                                 withLaunchLink:[NSURL URLWithString:@"https://teak.io/link/abc123"]];
    XCTAssertTrue(updated.isFinished);
    XCTAssertNotNil(updated.result);
    weakOriginal = original;
    weakUpdated = updated;
  }
  XCTAssertNil(weakOriginal);
  XCTAssertNil(weakUpdated);
}

// A universal link that can't be resolved (here a nil URL, which raises while
// building the request) must not take the host app down, and must still leave a
// result for the session to read.
- (void)testUnresolvableUniversalLinkFinishesWithUnattributedResult {
  TeakLaunchDataOperation* op = [TeakLaunchDataOperation fromUniversalLink:nil];
  [op start];
  XCTAssertTrue(op.isFinished);
  XCTAssertNotNil(op.result);
  XCTAssertNil(op.result.launchUrl);
}

- (void)testResultIsSetOnlyAfterRun {
  NSURL* url = [NSURL URLWithString:@"teaktest-app://store/coins"];
  TeakLaunchDataOperation* op = [TeakLaunchDataOperation fromOpenUrl:url];
  XCTAssertNil(op.result);
  [op start];
  XCTAssertEqualObjects(op.result.launchUrl, url);
}

@end
