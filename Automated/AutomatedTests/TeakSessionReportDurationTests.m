#import <XCTest/XCTest.h>

#import "TeakConfiguration.h"
#import "TeakSession.h"

@interface TeakSession (ReportDurationTesting)
@property (strong, atomic) dispatch_block_t reportDurationBlock;
@property (copy, atomic) void (^reportDurationClaimHook)(void);
- (BOOL)claimReportDuration:(int*)outVectorClock;
- (BOOL)resetReportDurationBlock;
@end

// A reset that lands while the duration report is being claimed must either cancel it before the
// claim, or see it as sent so the caller sends /session_resume. The claim hook parks the claim in
// its window (cancel check passed, not yet marked sent) and runs a reset on another thread there.
@interface TeakSessionReportDurationTests : XCTestCase
@end

@implementation TeakSessionReportDurationTests

// -[TeakSession init] reads TeakConfiguration.configuration; seed it once (another test class may
// have configured it already).
+ (void)setUp {
  [super setUp];
  @try {
    [TeakConfiguration configureForAppId:@"test-app" andSecret:@"test-secret"];
  } @catch (NSException* exception) {
  }
}

- (TeakSession*)sessionWithPendingReport {
  TeakSession* session = [[TeakSession alloc] init];
  session.reportDurationBlock = dispatch_block_create(0, ^{
  });
  return session;
}

- (void)testResetDuringClaimSeesReportAsSent {
  TeakSession* session = [self sessionWithPendingReport];

  __block BOOL resetSawSent = NO;
  dispatch_semaphore_t resetDone = dispatch_semaphore_create(0);
  session.reportDurationClaimHook = ^{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
      resetSawSent = [session resetReportDurationBlock];
      dispatch_semaphore_signal(resetDone);
    });
    // Give the reset time to finish if nothing holds it off. With the claim and reset serialized
    // this wait times out and the reset runs after the claim marks the report sent.
    if (dispatch_semaphore_wait(resetDone, dispatch_time(DISPATCH_TIME_NOW, 200 * NSEC_PER_MSEC)) == 0) {
      dispatch_semaphore_signal(resetDone);
    }
  };

  int vectorClock = 0;
  BOOL claimed = [session claimReportDuration:&vectorClock];
  XCTAssertEqual(dispatch_semaphore_wait(resetDone, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)), 0);

  XCTAssertTrue(claimed);
  XCTAssertEqual(vectorClock, 1);
  XCTAssertTrue(resetSawSent, @"a reset racing a claimed /session_stop must report it sent, or /session_resume is dropped");
}

- (void)testResetBeforeClaimCancelsReport {
  TeakSession* session = [self sessionWithPendingReport];

  XCTAssertFalse([session resetReportDurationBlock]);

  int vectorClock = 0;
  XCTAssertFalse([session claimReportDuration:&vectorClock]);
  XCTAssertFalse([session resetReportDurationBlock]);
}

- (void)testResetAfterClaimSeesReportAsSentOnce {
  TeakSession* session = [self sessionWithPendingReport];

  int vectorClock = 0;
  XCTAssertTrue([session claimReportDuration:&vectorClock]);
  XCTAssertTrue([session resetReportDurationBlock]);
  XCTAssertFalse([session resetReportDurationBlock]);
}

@end
