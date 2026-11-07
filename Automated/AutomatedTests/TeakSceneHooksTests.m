#import <XCTest/XCTest.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

extern Teak* _teakSharedInstance;

@interface TeakSceneHooks (Discovery)
+ (void)installForAppDelegateClass:(Class)appDelegateClass;
@end

// Every test builds its own classes at runtime: hooks are permanent, so classes can't be shared between tests.
static Class MakeClass(NSString* prefix, Class superclass) {
  static NSUInteger counter = 0;
  NSString* name = [NSString stringWithFormat:@"%@_%lu", prefix, (unsigned long)++counter];
  Class klass = objc_allocateClassPair(superclass, name.UTF8String, 0);
  objc_registerClassPair(klass);
  return klass;
}

// Gives klass a scene:openURLContexts: that bumps calls[key] — stands in for the host app's own implementation.
static void AddRecordingOpenURLContexts(Class klass, NSMutableDictionary<NSString*, NSNumber*>* calls, NSString* key) {
  IMP imp = imp_implementationWithBlock(^(id _self, UIScene* scene, NSSet* contexts) {
    calls[key] = @(calls[key].integerValue + 1);
  });
  class_addMethod(klass, @selector(scene:openURLContexts:), imp, "v@:@@");
}

@interface TeakSceneHooksTests : XCTestCase
@end

@implementation TeakSceneHooksTests {
  Teak* _savedSharedInstance;
  Teak* _teak;
  NSMutableDictionary<NSString*, NSNumber*>* _calls;
}

- (void)setUp {
  _savedSharedInstance = _teakSharedInstance;
  _teak = mock([Teak class]);
  _teakSharedInstance = _teak;
  _calls = [[NSMutableDictionary alloc] init];
}

- (void)tearDown {
  _teakSharedInstance = _savedSharedInstance;
}

- (NSSet<UIOpenURLContext*>*)contextsForURLs:(NSArray<NSURL*>*)urls {
  NSMutableSet* contexts = [[NSMutableSet alloc] init];
  for (NSURL* url in urls) {
    UIOpenURLContext* context = mock([UIOpenURLContext class]);
    [given(context.URL) willReturn:url];
    [contexts addObject:context];
  }
  return contexts;
}

- (void)openURL:(NSURL*)url on:(id)sceneDelegate {
  [sceneDelegate scene:mock([UIScene class]) openURLContexts:[self contextsForURLs:@[ url ]]];
}

#pragma mark - Discovery

// A UIKit app that picks its scene delegate class at runtime, in application:configurationForConnectingSceneSession:options:.
- (void)testSceneDelegateClassPickedAtRuntimeGetsLinkHooks {
  Class sceneDelegateClass = MakeClass(@"RuntimeSceneDelegate", [UIResponder class]);
  AddRecordingOpenURLContexts(sceneDelegateClass, _calls, @"host");

  Class appDelegateClass = MakeClass(@"RuntimeAppDelegate", [UIResponder class]);
  IMP configIMP = imp_implementationWithBlock(^UISceneConfiguration*(id _self, UIApplication* app, UISceneSession* session, UISceneConnectionOptions* options) {
    UISceneConfiguration* configuration = [UISceneConfiguration configurationWithName:@"Runtime" sessionRole:UIWindowSceneSessionRoleApplication];
    configuration.delegateClass = sceneDelegateClass;
    return configuration;
  });
  class_addMethod(appDelegateClass, @selector(application:configurationForConnectingSceneSession:options:), configIMP, "@@:@@@");

  [TeakSceneHooks installForAppDelegateClass:appDelegateClass];

  // Nothing is hooked until UIKit asks the app delegate which configuration to use.
  NSURL* before = [NSURL URLWithString:@"teak1234://before"];
  [self openURL:before on:[[sceneDelegateClass alloc] init]];
  [verifyCount(_teak, never()) application:anything() openURL:before sourceApplication:anything() annotation:anything()];

  UISceneConfiguration* returned = [[[appDelegateClass alloc] init] application:[UIApplication sharedApplication]
                                           configurationForConnectingSceneSession:mock([UISceneSession class])
                                                                          options:mock([UISceneConnectionOptions class])];
  XCTAssertEqual(returned.delegateClass, sceneDelegateClass, @"host's configuration is returned untouched");

  NSURL* after = [NSURL URLWithString:@"teak1234://after"];
  id sceneDelegate = [[sceneDelegateClass alloc] init];
  [self openURL:after on:sceneDelegate];
  [verifyCount(_teak, times(1)) application:anything() openURL:after sourceApplication:anything() annotation:anything()];
  XCTAssertEqual(_calls[@"host"].integerValue, 2, @"host implementation still runs, before and after hooking");

  // The delegate doesn't implement continueUserActivity; Teak adds it.
  NSUserActivity* activity = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
  [sceneDelegate scene:mock([UIScene class]) continueUserActivity:activity];
  [verifyCount(_teak, times(1)) application:anything() continueUserActivity:activity restorationHandler:anything()];
}

#pragma mark - Hook bookkeeping

- (void)testHookingTheSameClassTwiceCallsHostOnce {
  Class klass = MakeClass(@"TwiceSceneDelegate", [UIResponder class]);
  AddRecordingOpenURLContexts(klass, _calls, @"host");

  [TeakSceneHooks swizzleInto:klass];
  [TeakSceneHooks swizzleInto:klass];

  NSURL* url = [NSURL URLWithString:@"teak1234://twice"];
  [self openURL:url on:[[klass alloc] init]];

  XCTAssertEqual(_calls[@"host"].integerValue, 1);
  [verifyCount(_teak, times(1)) application:anything() openURL:url sourceApplication:anything() annotation:anything()];
}

- (void)testTwoClassesKeepTheirOwnOriginals {
  Class first = MakeClass(@"FirstSceneDelegate", [UIResponder class]);
  Class second = MakeClass(@"SecondSceneDelegate", [UIResponder class]);
  AddRecordingOpenURLContexts(first, _calls, @"first");
  AddRecordingOpenURLContexts(second, _calls, @"second");

  [TeakSceneHooks swizzleInto:first];
  [TeakSceneHooks swizzleInto:second];

  [self openURL:[NSURL URLWithString:@"teak1234://first"] on:[[first alloc] init]];
  XCTAssertEqual(_calls[@"first"].integerValue, 1);
  XCTAssertEqual(_calls[@"second"].integerValue, 0);

  [self openURL:[NSURL URLWithString:@"teak1234://second"] on:[[second alloc] init]];
  XCTAssertEqual(_calls[@"first"].integerValue, 1);
  XCTAssertEqual(_calls[@"second"].integerValue, 1);
}

- (void)testSuperclassThenSubclassCallsEachOnce {
  Class base = MakeClass(@"BaseSceneDelegate", [UIResponder class]);
  AddRecordingOpenURLContexts(base, _calls, @"base");
  Class sub = MakeClass(@"SubSceneDelegate", base);

  [TeakSceneHooks swizzleInto:base];
  [TeakSceneHooks swizzleInto:sub];

  NSURL* url = [NSURL URLWithString:@"teak1234://base-first"];
  [self openURL:url on:[[sub alloc] init]];
  XCTAssertEqual(_calls[@"base"].integerValue, 1);
  [verifyCount(_teak, times(1)) application:anything() openURL:url sourceApplication:anything() annotation:anything()];
}

- (void)testSubclassThenSuperclassCallsEachOnce {
  Class base = MakeClass(@"BaseSceneDelegate", [UIResponder class]);
  AddRecordingOpenURLContexts(base, _calls, @"base");
  Class sub = MakeClass(@"SubSceneDelegate", base);

  [TeakSceneHooks swizzleInto:sub];
  [TeakSceneHooks swizzleInto:base];

  NSURL* subURL = [NSURL URLWithString:@"teak1234://sub-first"];
  [self openURL:subURL on:[[sub alloc] init]];
  XCTAssertEqual(_calls[@"base"].integerValue, 1);
  [verifyCount(_teak, times(1)) application:anything() openURL:subURL sourceApplication:anything() annotation:anything()];

  NSURL* baseURL = [NSURL URLWithString:@"teak1234://base"];
  [self openURL:baseURL on:[[base alloc] init]];
  XCTAssertEqual(_calls[@"base"].integerValue, 2);
  [verifyCount(_teak, times(1)) application:anything() openURL:baseURL sourceApplication:anything() annotation:anything()];
}

#pragma mark - Routing

- (void)testWillConnectRoutesEveryLaunchURLAndActivity {
  Class klass = MakeClass(@"LaunchSceneDelegate", [UIResponder class]);
  [TeakSceneHooks swizzleInto:klass];

  NSURL* one = [NSURL URLWithString:@"teak1234://one"];
  NSURL* two = [NSURL URLWithString:@"teak1234://two"];
  NSUserActivity* activity = [[NSUserActivity alloc] initWithActivityType:NSUserActivityTypeBrowsingWeb];
  UISceneConnectionOptions* options = mock([UISceneConnectionOptions class]);
  [given(options.URLContexts) willReturn:[self contextsForURLs:@[ one, two ]]];
  [given(options.userActivities) willReturn:[NSSet setWithObject:activity]];

  [[[klass alloc] init] scene:mock([UIScene class]) willConnectToSession:mock([UISceneSession class]) options:options];

  [verifyCount(_teak, times(1)) application:anything() openURL:one sourceApplication:anything() annotation:anything()];
  [verifyCount(_teak, times(1)) application:anything() openURL:two sourceApplication:anything() annotation:anything()];
  [verifyCount(_teak, times(1)) application:anything() continueUserActivity:activity restorationHandler:anything()];
}

@end
