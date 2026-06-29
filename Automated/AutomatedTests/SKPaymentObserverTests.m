#import <XCTest/XCTest.h>

#import "SKPaymentObserver.h"
#import "TeakRaven.h"

// SKPaymentObserver.transactionDateFormatter is private — re-declare for test access.
@interface SKPaymentObserver (Testing)
+ (NSDateFormatter*)transactionDateFormatter;
@end

// TeakRavenReport is defined in TeakRaven.m; dateFormatter is its only method we need.
@interface TeakRavenReport : NSObject
+ (NSDateFormatter*)dateFormatter;
@end

@interface SKPaymentObserverTests : XCTestCase
@end

@implementation SKPaymentObserverTests

// Verifies purchase_time uses en_US_POSIX so Arabic-locale devices don't produce
// Eastern-Arabic numerals the server can't parse (C-302 / ArgumentError: mon out of range).
- (void)testPurchaseTimeDateFormatterProducesLocaleIndependentOutput {
  NSDate* date = [NSDate dateWithTimeIntervalSince1970:1705319445]; // 2024-01-15T11:50:45 UTC
  NSString* formatted = [[SKPaymentObserver transactionDateFormatter] stringFromDate:date];
  XCTAssertEqualObjects(formatted, @"2024-01-15T11:50:45+0000",
                        @"purchase_time must use ASCII digits regardless of device locale");
}

// Verifies the Sentry timestamp formatter (TeakRaven) has the same en_US_POSIX fix applied.
// en_US_POSIX pins digits to ASCII without changing the ISO8601 format Sentry expects.
- (void)testRavenDateFormatterProducesLocaleIndependentOutput {
  NSDate* date = [NSDate dateWithTimeIntervalSince1970:1705319445]; // 2024-01-15T11:50:45 UTC
  NSString* formatted = [[TeakRavenReport dateFormatter] stringFromDate:date];
  XCTAssertEqualObjects(formatted, @"2024-01-15T11:50:45",
                        @"Sentry timestamp must use ASCII digits regardless of device locale");
}

@end
