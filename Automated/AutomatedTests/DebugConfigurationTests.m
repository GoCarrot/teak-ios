#import <XCTest/XCTest.h>

#import "../../Teak/Configuration/TeakDebugConfiguration.h"

@interface DebugConfigurationTests : XCTestCase
@end

@implementation DebugConfigurationTests

#pragma mark - TeakForceDebugOutput Info.plist key

- (void)testLogLocalIsYesWhenInfoPlistForceDebugOutputIsYes {
  NSUserDefaults* defaults = [[NSUserDefaults alloc] initWithSuiteName:@"TestDefaults_forceYes"];
  [defaults setBool:NO forKey:@"TeakLogLocal"];
  [defaults setBool:NO forKey:@"TeakLogRemote"];

  NSDictionary* infoDictionary = @{@"TeakForceDebugOutput" : @YES};

  TeakDebugConfiguration* config = [[TeakDebugConfiguration alloc] initWithUserDefaults:defaults
                                                                         infoDictionary:infoDictionary];

  XCTAssertTrue(config.logLocal, @"logLocal should be YES when TeakForceDebugOutput is YES in Info.plist");

  [defaults removePersistentDomainForName:@"TestDefaults_forceYes"];
}

- (void)testLogLocalIsNoWhenInfoPlistKeyAbsentAndDefaultsNo {
  NSUserDefaults* defaults = [[NSUserDefaults alloc] initWithSuiteName:@"TestDefaults_absent"];
  [defaults setBool:NO forKey:@"TeakLogLocal"];
  [defaults setBool:NO forKey:@"TeakLogRemote"];

  NSDictionary* infoDictionary = @{};

  TeakDebugConfiguration* config = [[TeakDebugConfiguration alloc] initWithUserDefaults:defaults
                                                                         infoDictionary:infoDictionary];

  XCTAssertFalse(config.logLocal, @"logLocal should be NO when Info.plist key is absent and defaults are NO");

  [defaults removePersistentDomainForName:@"TestDefaults_absent"];
}

- (void)testLogLocalIsYesWhenDefaultsYesAndInfoPlistKeyAbsent {
  NSUserDefaults* defaults = [[NSUserDefaults alloc] initWithSuiteName:@"TestDefaults_defaultsYes"];
  [defaults setBool:YES forKey:@"TeakLogLocal"];
  [defaults setBool:NO forKey:@"TeakLogRemote"];

  NSDictionary* infoDictionary = @{};

  TeakDebugConfiguration* config = [[TeakDebugConfiguration alloc] initWithUserDefaults:defaults
                                                                         infoDictionary:infoDictionary];

  XCTAssertTrue(config.logLocal, @"logLocal should be YES when NSUserDefaults has TeakLogLocal=YES");

  [defaults removePersistentDomainForName:@"TestDefaults_defaultsYes"];
}

- (void)testLogLocalIsYesWhenBothInfoPlistAndDefaultsAreYes {
  NSUserDefaults* defaults = [[NSUserDefaults alloc] initWithSuiteName:@"TestDefaults_bothYes"];
  [defaults setBool:YES forKey:@"TeakLogLocal"];
  [defaults setBool:NO forKey:@"TeakLogRemote"];

  NSDictionary* infoDictionary = @{@"TeakForceDebugOutput" : @YES};

  TeakDebugConfiguration* config = [[TeakDebugConfiguration alloc] initWithUserDefaults:defaults
                                                                         infoDictionary:infoDictionary];

  XCTAssertTrue(config.logLocal, @"logLocal should be YES when both sources say YES");

  [defaults removePersistentDomainForName:@"TestDefaults_bothYes"];
}

- (void)testLogLocalIsNoWhenInfoPlistForceDebugOutputIsNo {
  NSUserDefaults* defaults = [[NSUserDefaults alloc] initWithSuiteName:@"TestDefaults_forceNo"];
  [defaults setBool:NO forKey:@"TeakLogLocal"];
  [defaults setBool:NO forKey:@"TeakLogRemote"];

  NSDictionary* infoDictionary = @{@"TeakForceDebugOutput" : @NO};

  TeakDebugConfiguration* config = [[TeakDebugConfiguration alloc] initWithUserDefaults:defaults
                                                                         infoDictionary:infoDictionary];

  XCTAssertFalse(config.logLocal, @"logLocal should be NO when Info.plist is NO and defaults are NO");

  [defaults removePersistentDomainForName:@"TestDefaults_forceNo"];
}

#pragma mark - logRemote is unaffected by Info.plist

- (void)testLogRemoteUnaffectedByInfoPlistKey {
  NSUserDefaults* defaults = [[NSUserDefaults alloc] initWithSuiteName:@"TestDefaults_remote"];
  [defaults setBool:NO forKey:@"TeakLogLocal"];
  [defaults setBool:NO forKey:@"TeakLogRemote"];

  NSDictionary* infoDictionary = @{@"TeakForceDebugOutput" : @YES};

  TeakDebugConfiguration* config = [[TeakDebugConfiguration alloc] initWithUserDefaults:defaults
                                                                         infoDictionary:infoDictionary];

  XCTAssertFalse(config.logRemote, @"logRemote should not be affected by TeakForceDebugOutput");

  [defaults removePersistentDomainForName:@"TestDefaults_remote"];
}

- (void)testLogRemoteFollowsDefaults {
  NSUserDefaults* defaults = [[NSUserDefaults alloc] initWithSuiteName:@"TestDefaults_remoteYes"];
  [defaults setBool:NO forKey:@"TeakLogLocal"];
  [defaults setBool:YES forKey:@"TeakLogRemote"];

  NSDictionary* infoDictionary = @{};

  TeakDebugConfiguration* config = [[TeakDebugConfiguration alloc] initWithUserDefaults:defaults
                                                                         infoDictionary:infoDictionary];

  XCTAssertTrue(config.logRemote, @"logRemote should follow NSUserDefaults value");

  [defaults removePersistentDomainForName:@"TestDefaults_remoteYes"];
}

#pragma mark - setLogLocal:logRemote: persists to injected defaults

- (void)testSetLogLocalLogRemotePersistsToDefaults {
  NSUserDefaults* defaults = [[NSUserDefaults alloc] initWithSuiteName:@"TestDefaults_persist"];
  [defaults setBool:NO forKey:@"TeakLogLocal"];
  [defaults setBool:NO forKey:@"TeakLogRemote"];

  TeakDebugConfiguration* config = [[TeakDebugConfiguration alloc] initWithUserDefaults:defaults
                                                                         infoDictionary:@{}];

  [config setLogLocal:YES logRemote:YES];

  XCTAssertTrue(config.logLocal, @"logLocal should be YES after setLogLocal:YES");
  XCTAssertTrue(config.logRemote, @"logRemote should be YES after setLogLocal:logRemote:YES");
  XCTAssertTrue([defaults boolForKey:@"TeakLogLocal"], @"NSUserDefaults should persist logLocal");
  XCTAssertTrue([defaults boolForKey:@"TeakLogRemote"], @"NSUserDefaults should persist logRemote");

  [defaults removePersistentDomainForName:@"TestDefaults_persist"];
}

@end
