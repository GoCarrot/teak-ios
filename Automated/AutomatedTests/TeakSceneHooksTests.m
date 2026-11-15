#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>

#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

extern Teak* _teakSharedInstance;

extern void TeakLifecycleDidBecomeActive(UIApplication* application);
extern void TeakLifecycleWillResignActive(UIApplication* application);
extern void TeakLifecycleInstall(void);
extern void TeakLifecycleSeed(void);

@interface TeakSceneHooksTests : XCTestCase
@end

@implementation TeakSceneHooksTests {
  Teak* _savedSharedInstance;
  Teak* _teak;
}

- (void)setUp {
  _savedSharedInstance = _teakSharedInstance;
  [self freshTeak];
}

- (void)tearDown {
  _teakSharedInstance = _savedSharedInstance;
}

- (Teak*)freshTeak {
  _teak = mock([Teak class]);
  _teakSharedInstance = _teak;
  return _teak;
}

#pragma mark - Lifecycle

- (void)testLifecycleRunsOncePerTransitionAcrossDelegateAndNotification {
  TeakLifecycleInstall();
  TeakLifecycleWillResignActive(nil);

  // Scene apps: only the notification arrives.
  Teak* teak = [self freshTeak];
  [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
  [verifyCount(teak, times(1)) applicationDidBecomeActive:anything()];

  teak = [self freshTeak];
  [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationWillResignActiveNotification object:nil];
  [verifyCount(teak, times(1)) applicationWillResignActive:anything()];

  // App delegate apps: the delegate hook arrives first, then the notification.
  teak = [self freshTeak];
  TeakLifecycleDidBecomeActive(nil);
  [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
  [verifyCount(teak, times(1)) applicationDidBecomeActive:anything()];

  teak = [self freshTeak];
  TeakLifecycleWillResignActive(nil);
  [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationWillResignActiveNotification object:nil];
  [verifyCount(teak, times(1)) applicationWillResignActive:anything()];
}

- (void)testOffMainSeedOfAnActiveAppLetsTheNextResignThrough {
  XCTAssertEqual([UIApplication sharedApplication].applicationState, UIApplicationStateActive, @"test host must be active");
  TeakLifecycleInstall();
  TeakLifecycleWillResignActive(nil);

  XCTestExpectation* planted = [self expectationWithDescription:@"seeded off main"];
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
    TeakLifecycleSeed();
    // The seed hops to main; this block queues behind it.
    dispatch_async(dispatch_get_main_queue(), ^{
      [planted fulfill];
    });
  });
  [self waitForExpectations:@[ planted ] timeout:5];

  Teak* teak = [self freshTeak];
  [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationWillResignActiveNotification object:nil];
  [verifyCount(teak, times(1)) applicationWillResignActive:anything()];
}

@end
