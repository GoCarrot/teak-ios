#import <XCTest/XCTest.h>

#import "TeakLog.h"
#import "TeakRaven.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

@interface TeakRavenLocationHelper (LogTestAccess)
@property (strong, nonatomic) NSMutableArray* breadcrumbs;
@end

@interface LogTests : XCTestCase
@property (strong, nonatomic) TeakLog* log;
@property (strong, nonatomic) Teak* teakMock;
@end

@implementation LogTests

- (void)setUp {
  self.teakMock = mock([Teak class]);
  [given([self.teakMock enableRemoteLogging]) willReturn:@NO];
  [given([self.teakMock enableDebugOutput]) willReturn:@NO];

  self.log = [[TeakLog alloc] initForTeak:self.teakMock withAppId:@"automated"];
}

- (void)testExample {
  __block NSNumber* listenerCalled = @NO;
  stubProperty(self.teakMock, logListener,
               ^(NSString* _Nonnull event,
                 NSString* _Nonnull level,
                 NSDictionary* _Nullable eventData) {
                 listenerCalled = @YES;

                 assertThat(event, is(@"test"));
                 assertThat(level, is(@"INFO"));
               });
  [self.log logEvent:@"test" level:@"INFO" eventData:@{}];
  assertThat(listenerCalled, is(@YES));
}

- (void)testLogEventAddsBreadcrumbToActiveHelper {
  TeakRavenLocationHelper* helper = [TeakRavenLocationHelper pushHelperForFile:__FILE__ line:__LINE__ function:__PRETTY_FUNCTION__];

  [self.log logEvent:@"test.breadcrumb" level:@"INFO" eventData:@{@"key" : @"value"}];

  [TeakRavenLocationHelper popHelper];

  assertThat(helper.breadcrumbs, hasCountOf(1));
  NSDictionary* breadcrumb = helper.breadcrumbs[0];
  assertThat(breadcrumb[@"category"], is(@"INFO"));
  assertThat(breadcrumb[@"message"], is(@"test.breadcrumb"));
  assertThat(breadcrumb[@"data"][@"key"], is(@"value"));
}

- (void)testLogEventOutsideTryDoesNotCrash {
  XCTAssertNil([TeakRavenLocationHelper peekHelper]);
  XCTAssertNoThrow([self.log logEvent:@"test.no.helper" level:@"INFO" eventData:@{}]);
}

- (void)testBreadcrumbCapAt100 {
  TeakRavenLocationHelper* helper = [TeakRavenLocationHelper pushHelperForFile:__FILE__ line:__LINE__ function:__PRETTY_FUNCTION__];

  for (int i = 0; i < 110; i++) {
    [self.log logEvent:@"test.volume" level:@"INFO" eventData:@{}];
  }

  [TeakRavenLocationHelper popHelper];

  assertThat(helper.breadcrumbs, hasCountOf(100));
}

@end
