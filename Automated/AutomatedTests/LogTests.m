#import <XCTest/XCTest.h>

#import "TeakLog.h"
#import "TeakRaven.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

@interface LogTests : XCTestCase
@property (strong, nonatomic) TeakLog* log;
@property (strong, nonatomic) Teak* teakMock;
@end

@implementation LogTests

- (void)setUp {
  [[TeakRavenLocationHelper sharedBreadcrumbs] removeAllObjects];
  while ([TeakRavenLocationHelper peekHelper] != nil) {
    [TeakRavenLocationHelper popHelper];
  }

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

- (void)testLogEventAddsBreadcrumb {
  [self.log logEvent:@"test.breadcrumb" level:@"INFO" eventData:@{@"key" : @"value"}];

  NSMutableArray* breadcrumbs = [TeakRavenLocationHelper sharedBreadcrumbs];
  assertThat(breadcrumbs, hasCountOf(1));
  NSDictionary* breadcrumb = breadcrumbs[0];
  assertThat(breadcrumb[@"category"], is(@"test.breadcrumb"));
  assertThat(breadcrumb[@"data"][@"key"], is(@"value"));
  assertThat(breadcrumb[@"data"][@"log_level"], is(@"INFO"));
}

- (void)testLogEventOutsideTryDoesNotCrash {
  XCTAssertNil([TeakRavenLocationHelper peekHelper]);
  XCTAssertNoThrow([self.log logEvent:@"test.no.helper" level:@"INFO" eventData:@{}]);
}

- (void)testBreadcrumbCapAt100 {
  for (int i = 0; i < 110; i++) {
    [self.log logEvent:@"test.volume" level:@"INFO" eventData:@{@"i" : @(i)}];
  }

  NSMutableArray* breadcrumbs = [TeakRavenLocationHelper sharedBreadcrumbs];
  assertThat(breadcrumbs, hasCountOf(100));
  // Oldest-kept entry is event index 10 (events 0–9 were evicted); verifies FIFO eviction.
  assertThat(breadcrumbs[0][@"data"][@"i"], equalTo(@10));
}

@end
