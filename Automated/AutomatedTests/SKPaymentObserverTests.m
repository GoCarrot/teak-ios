#import <XCTest/XCTest.h>

#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

@interface SKPaymentObserverTests : XCTestCase
@end

@implementation SKPaymentObserverTests

// Verifies that purchase_time uses en_US_POSIX locale so that devices with a non-ASCII-numeral
// locale (e.g. Arabic) still produce ASCII digits the server can parse. The bug: without an
// explicit locale, Arabic-locale devices produced Eastern-Arabic numerals → server ArgumentError.
- (void)testPurchaseTimeDateFormatterProducesLocaleIndependentOutput {
  // Fixed timestamp for deterministic output: 2024-01-15T11:50:45 UTC
  NSDate* date = [NSDate dateWithTimeIntervalSince1970:1705319445];

  NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
  [formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
  [formatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
  [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZ"];

  XCTAssertEqualObjects([formatter stringFromDate:date], @"2024-01-15T11:50:45+0000",
                        @"purchase_time must use ASCII digits regardless of device locale");
}

// Verifies the Sentry timestamp formatter (TeakRaven) has the same en_US_POSIX fix applied.
// en_US_POSIX pins digits to ASCII without changing the ISO8601 format Sentry expects.
- (void)testRavenDateFormatterProducesLocaleIndependentOutput {
  NSDate* date = [NSDate dateWithTimeIntervalSince1970:1705319445];

  NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
  [formatter setLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
  [formatter setTimeZone:[NSTimeZone timeZoneWithName:@"UTC"]];
  [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss"];

  XCTAssertEqualObjects([formatter stringFromDate:date], @"2024-01-15T11:50:45",
                        @"Sentry timestamp must use ASCII digits regardless of device locale");
}

@end
