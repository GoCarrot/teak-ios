#import <Foundation/Foundation.h>

extern NSDictionary* TeakVersionDict;

// The AutomatedTests bundle's principal class (NSPrincipalClass in Info.plist). XCTest creates one
// instance when the bundle loads, before any test runs, so state every test needs is set up here once.
@interface TeakTestBundleSetup : NSObject
@end

@implementation TeakTestBundleSetup

- (instancetype)init {
  self = [super init];
  if (self) {
    // Set by Teak's own init, which the test host never runs. Every TeakRequest's common payload
    // includes it, and building that payload with it nil throws.
    if (TeakVersionDict == nil) {
      TeakVersionDict = @{@"ios" : @"test"};
    }
  }
  return self;
}

@end
