#import <XCTest/XCTest.h>

#import "../../Teak/TeakLog.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

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

@end
