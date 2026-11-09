#import <XCTest/XCTest.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

#import <Teak/Teak.h>

@import OCHamcrest;
@import OCMockito;

extern Teak* _teakSharedInstance;

@interface TeakSceneHooks (Discovery)
+ (void)installForAppDelegateClass:(Class)appDelegateClass hostHandlesUserActivity:(BOOL)hostHandlesUserActivity;
@end

@interface Teak (SceneHooksTesting)
- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation;
@end

extern void TeakLifecycleDidBecomeActive(UIApplication* application);
extern void TeakLifecycleWillResignActive(UIApplication* application);
extern void TeakLifecycleInstall(void);

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
    calls[[key stringByAppendingString:@".contexts"]] = @(calls[[key stringByAppendingString:@".contexts"]].integerValue + contexts.count);
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
  [self freshTeak];
  _calls = [[NSMutableDictionary alloc] init];
}

- (void)tearDown {
  _teakSharedInstance = _savedSharedInstance;
}

- (Teak*)freshTeak {
  _teak = mock([Teak class]);
  _teakSharedInstance = _teak;
  return _teak;
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

  [TeakSceneHooks installForAppDelegateClass:appDelegateClass hostHandlesUserActivity:NO];

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

// A relaunch restores the scene session the app delegate configured earlier; UIKit doesn't ask again.
- (void)testRestoredSessionDelegateClassIsHookedAtLaunch {
  [TeakSceneHooks installForAppDelegateClass:nil hostHandlesUserActivity:NO];
  Class sceneDelegateClass = MakeClass(@"RestoredSceneDelegate", [UIResponder class]);
  UISceneConfiguration* configuration = [UISceneConfiguration configurationWithName:@"Restored" sessionRole:UIWindowSceneSessionRoleApplication];
  configuration.delegateClass = sceneDelegateClass;
  UISceneSession* session = mock([UISceneSession class]);
  [given(session.configuration) willReturn:configuration];
  UIApplication* application = mock([UIApplication class]);
  [given(application.openSessions) willReturn:[NSSet setWithObject:session]];

  XCTAssertFalse([sceneDelegateClass instancesRespondToSelector:@selector(scene:willConnectToSession:options:)]);
  [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidFinishLaunchingNotification object:application];

  NSURL* url = [NSURL URLWithString:@"teak1234://restored"];
  UISceneConnectionOptions* options = mock([UISceneConnectionOptions class]);
  [given(options.URLContexts) willReturn:[self contextsForURLs:@[ url ]]];
  [[[sceneDelegateClass alloc] init] scene:mock([UIScene class]) willConnectToSession:mock([UISceneSession class]) options:options];
  [verifyCount(_teak, times(1)) application:anything() openURL:url sourceApplication:anything() annotation:anything()];
}

#pragma mark - Hook bookkeeping

- (void)testHookingTheSameClassTwiceCallsHostOnce {
  Class klass = MakeClass(@"TwiceSceneDelegate", [UIResponder class]);
  AddRecordingOpenURLContexts(klass, _calls, @"host");

  [TeakSceneHooks swizzleInto:klass];
  IMP hooked = class_getMethodImplementation(klass, @selector(scene:openURLContexts:));
  [TeakSceneHooks swizzleInto:klass];
  XCTAssertEqual(class_getMethodImplementation(klass, @selector(scene:openURLContexts:)), hooked, @"second hook is a no-op");

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

// Either hooking order: the subclass inherits the superclass's method, which runs once.
- (void)testSubclassAndSuperclassHookedInEitherOrderCallEachOnce {
  for (NSNumber* superclassFirst in @[ @YES, @NO ]) {
    Class base = MakeClass(@"BaseSceneDelegate", [UIResponder class]);
    Class sub = MakeClass(@"SubSceneDelegate", base);
    NSString* key = superclassFirst.boolValue ? @"superclassFirst" : @"subclassFirst";
    AddRecordingOpenURLContexts(base, _calls, key);

    if (superclassFirst.boolValue) {
      [TeakSceneHooks swizzleInto:base];
      [TeakSceneHooks swizzleInto:sub];
    } else {
      [TeakSceneHooks swizzleInto:sub];
      [TeakSceneHooks swizzleInto:base];
    }

    NSURL* url = [NSURL URLWithString:[@"teak1234://" stringByAppendingString:key]];
    [self openURL:url on:[[sub alloc] init]];
    XCTAssertEqual(_calls[key].integerValue, 1, @"%@", key);
    [verifyCount(_teak, times(1)) application:anything() openURL:url sourceApplication:anything() annotation:anything()];
  }
}

// B overrides scene:openURLContexts: and calls super into A; both hooked.
- (void)testOverrideCallingSuperRunsEachHostOnceAndTeakOnce {
  Class base = MakeClass(@"SuperBaseSceneDelegate", [UIResponder class]);
  AddRecordingOpenURLContexts(base, _calls, @"base");
  Class sub = MakeClass(@"SuperSubSceneDelegate", base);
  NSMutableDictionary<NSString*, NSNumber*>* calls = _calls;
  IMP subIMP = imp_implementationWithBlock(^(id _self, UIScene* scene, NSSet* contexts) {
    calls[@"sub"] = @(calls[@"sub"].integerValue + 1);
    struct objc_super sup = {_self, base};
    ((void (*)(struct objc_super*, SEL, UIScene*, NSSet*))objc_msgSendSuper)(&sup, @selector(scene:openURLContexts:), scene, contexts);
  });
  class_addMethod(sub, @selector(scene:openURLContexts:), subIMP, "v@:@@");

  [TeakSceneHooks swizzleInto:base];
  [TeakSceneHooks swizzleInto:sub];

  NSURL* url = [NSURL URLWithString:@"teak1234://super"];
  [self openURL:url on:[[sub alloc] init]];
  XCTAssertEqual(_calls[@"sub"].integerValue, 1);
  XCTAssertEqual(_calls[@"base"].integerValue, 1);
  [verifyCount(_teak, times(1)) application:anything() openURL:url sourceApplication:anything() annotation:anything()];
}

- (void)testContinueUserActivityNotAddedWhenHostAppDelegateHandlesIt {
  Class sceneDelegateClass = MakeClass(@"HostActivitySceneDelegate", [UIResponder class]);
  Class appDelegateClass = MakeClass(@"HostActivityAppDelegate", [UIResponder class]);
  IMP configIMP = imp_implementationWithBlock(^UISceneConfiguration*(id _self, UIApplication* app, UISceneSession* session, UISceneConnectionOptions* options) {
    UISceneConfiguration* configuration = [UISceneConfiguration configurationWithName:@"Runtime" sessionRole:UIWindowSceneSessionRoleApplication];
    configuration.delegateClass = sceneDelegateClass;
    return configuration;
  });
  class_addMethod(appDelegateClass, @selector(application:configurationForConnectingSceneSession:options:), configIMP, "@@:@@@");

  [TeakSceneHooks installForAppDelegateClass:appDelegateClass hostHandlesUserActivity:YES];
  [[[appDelegateClass alloc] init] application:[UIApplication sharedApplication]
       configurationForConnectingSceneSession:mock([UISceneSession class])
                                      options:mock([UISceneConnectionOptions class])];

  XCTAssertFalse([sceneDelegateClass instancesRespondToSelector:@selector(scene:continueUserActivity:)]);
  XCTAssertTrue([sceneDelegateClass instancesRespondToSelector:@selector(scene:openURLContexts:)]);
}

#pragma mark - Routing

- (void)testTeakHandledContextsAreWithheldFromUIKitHost {
  Class klass = MakeClass(@"WithholdSceneDelegate", [UIResponder class]);
  AddRecordingOpenURLContexts(klass, _calls, @"host");
  [TeakSceneHooks swizzleInto:klass];

  NSURL* teakURL = [NSURL URLWithString:@"teak1234://teak-route"];
  NSURL* hostURL = [NSURL URLWithString:@"teak1234://host-route"];
  [given([_teak application:anything() openURL:teakURL sourceApplication:anything() annotation:anything()]) willReturnBool:YES];
  id sceneDelegate = [[klass alloc] init];

  [sceneDelegate scene:mock([UIScene class]) openURLContexts:[self contextsForURLs:@[ teakURL, hostURL ]]];
  XCTAssertEqual(_calls[@"host"].integerValue, 1);
  XCTAssertEqual(_calls[@"host.contexts"].integerValue, 1, @"only the context Teak didn't handle reaches the host");

  [self openURL:teakURL on:sceneDelegate];
  XCTAssertEqual(_calls[@"host"].integerValue, 1, @"host isn't called when Teak handled every context");
}

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

#pragma mark - Lifecycle

- (void)testLifecycleRunsOncePerTransitionAcrossDelegateAndNotification {
  TeakLifecycleInstall();
  TeakLifecycleWillResignActive(nil);

  // Scene apps: only the notification arrives.
  Teak* teak = [self freshTeak];
  [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
  [verifyCount(teak, times(1)) applicationDidBecomeActive:anything()];

  teak = [self freshTeak];
  [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationWillResignActiveNotification object:nil];
  [verifyCount(teak, times(1)) applicationWillResignActive:anything()];

  // App delegate apps: the delegate hook arrives first, then the notification.
  teak = [self freshTeak];
  TeakLifecycleDidBecomeActive(nil);
  [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
  [verifyCount(teak, times(1)) applicationDidBecomeActive:anything()];

  teak = [self freshTeak];
  TeakLifecycleWillResignActive(nil);
  [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationWillResignActiveNotification object:nil];
  [verifyCount(teak, times(1)) applicationWillResignActive:anything()];
}

@end
