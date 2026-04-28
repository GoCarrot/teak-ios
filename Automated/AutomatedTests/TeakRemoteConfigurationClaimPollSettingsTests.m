#import <XCTest/XCTest.h>

#import "TeakRemoteConfiguration.h"
#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

// Static helper under test — re-exposed for the test target. Bridges the
// wire/SDK unit boundary for the JWT-claim poll cadence settings emitted
// by Carrot's GamesController#settings.
@interface TeakRemoteConfiguration (TestAccess)
+ (NSTimeInterval)secondsFromReply:(NSDictionary*)reply
                               key:(NSString*)key
                          fallback:(NSTimeInterval)fallback;
@end

@interface TeakRemoteConfigurationClaimPollSettingsTests : XCTestCase
@end

@implementation TeakRemoteConfigurationClaimPollSettingsTests

#pragma mark - Wire field present and numeric

/// Wire field carries integer milliseconds; SDK property is NSTimeInterval
/// seconds. The helper divides by 1000.
- (void)testNumericMillisecondsAreConvertedToSeconds {
  NSDictionary* reply = @{@"claim_poll_initial_delay_ms" : @1500};
  NSTimeInterval seconds = [TeakRemoteConfiguration secondsFromReply:reply
                                                                 key:@"claim_poll_initial_delay_ms"
                                                            fallback:2.0];
  XCTAssertEqualWithAccuracy(seconds, 1.5, 0.001);
}

/// Floating-point milliseconds (defensive — server should always emit
/// integers, but any NSNumber subclass works).
- (void)testFloatingPointMillisecondsAreConvertedToSeconds {
  NSDictionary* reply = @{@"claim_poll_ceiling_ms" : @45000.5};
  NSTimeInterval seconds = [TeakRemoteConfiguration secondsFromReply:reply
                                                                 key:@"claim_poll_ceiling_ms"
                                                            fallback:30.0];
  XCTAssertEqualWithAccuracy(seconds, 45.0005, 0.0001);
}

/// Field-not-present in the reply leaves the caller's fallback in place.
/// The settings.json schema marks these columns nullable on Game, so a
/// game with no override gets the SDK-baked defaults.
- (void)testMissingFieldReturnsFallback {
  NSDictionary* reply = @{@"unrelated_field" : @123};
  NSTimeInterval seconds = [TeakRemoteConfiguration secondsFromReply:reply
                                                                 key:@"claim_poll_initial_delay_ms"
                                                            fallback:2.0];
  XCTAssertEqualWithAccuracy(seconds, 2.0, 0.001);
}

/// NSNull (the JSON-decoded form of `null`) returns the fallback.
- (void)testNullValueReturnsFallback {
  NSDictionary* reply = @{@"claim_poll_initial_delay_ms" : [NSNull null]};
  NSTimeInterval seconds = [TeakRemoteConfiguration secondsFromReply:reply
                                                                 key:@"claim_poll_initial_delay_ms"
                                                            fallback:2.0];
  XCTAssertEqualWithAccuracy(seconds, 2.0, 0.001);
}

/// Non-numeric value (defensive — guards against schema drift on the
/// server side) returns the fallback rather than NaN-ing the property.
- (void)testNonNumericValueReturnsFallback {
  NSDictionary* reply = @{@"claim_poll_ceiling_ms" : @"not_a_number"};
  NSTimeInterval seconds = [TeakRemoteConfiguration secondsFromReply:reply
                                                                 key:@"claim_poll_ceiling_ms"
                                                            fallback:30.0];
  XCTAssertEqualWithAccuracy(seconds, 30.0, 0.001);
}

@end
