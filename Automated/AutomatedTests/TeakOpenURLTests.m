#import <XCTest/XCTest.h>

#import <Teak/Teak.h>
#import <UIKit/UIKit.h>

@import OCHamcrest;
@import OCMockito;

// Declared in Teak+Internal.h, which is not on the test target's search path.
void TeakOpenURLInApplication(UIApplication* _Nonnull application, NSURL* _Nonnull url, NSString* _Nonnull logEvent);

@interface TeakOpenURLTests : XCTestCase
@end

@implementation TeakOpenURLTests

- (void)testOpensWithModernSelectorOnMainThread {
  id application = mock([UIApplication class]);
  NSURL* url = [NSURL URLWithString:@"app-settings:"];

  TeakOpenURLInApplication(application, url, @"test.open_attempt");

  [verify(application) openURL:url options:anything() completionHandler:anything()];
}

- (void)testHopsToMainThreadWhenCalledOffMain {
  id application = mock([UIApplication class]);
  NSURL* url = [NSURL URLWithString:@"app-settings:"];
  XCTestExpectation* opened = [self expectationWithDescription:@"openURL:options:completionHandler: called"];

  __block BOOL calledOnMain = NO;
  [givenVoid([application openURL:url options:anything() completionHandler:anything()])
      willDo:^id(NSInvocation* invocation) {
        calledOnMain = [NSThread isMainThread];
        [opened fulfill];
        return nil;
      }];

  dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
    TeakOpenURLInApplication(application, url, @"test.open_attempt");
  });

  [self waitForExpectationsWithTimeout:5 handler:nil];
  XCTAssertTrue(calledOnMain);
}

@end
