#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "TeakSceneHooks.h"
#import <Teak/Teak.h>
#import "Teak+Internal.h"

// Scene delegate hooks. Each hooked class gets its own hook IMP capturing that class's original.
//
// scene:openURLContexts: is added when the delegate lacks it: in scene apps, UIKit does not fall back
// to the app delegate's application:openURL:options: (measured on iOS 18.6). Whether UIKit falls back
// to application:continueUserActivity:restorationHandler: is unmeasured, so scene:continueUserActivity:
// is only added when the host app delegate doesn't implement that method. If there is a fallback,
// Teak's app delegate hook already sees the activity; if there isn't, the host's own universal links
// were already dead.
//
// Teak-handled URL contexts are withheld from UIKit scene delegates, as the app delegate hooks do.
// SwiftUI.AppSceneDelegate keeps getting every context, so SwiftUI apps still see onOpenURL for
// Teak links.

typedef UISceneConfiguration* (*TeakConfigurationIMP)(id, SEL, UIApplication*, UISceneSession*, UISceneConnectionOptions*);
typedef void (*TeakWillConnectIMP)(id, SEL, UIScene*, UISceneSession*, UISceneConnectionOptions*);
typedef void (*TeakOpenURLContextsIMP)(id, SEL, UIScene*, NSSet<UIOpenURLContext*>*);
typedef void (*TeakContinueUserActivityIMP)(id, SEL, UIScene*, NSUserActivity*);
typedef IMP (*TeakHookFactory)(SEL sel, IMP original, BOOL option);

@implementation TeakSceneHooks

static NSObject* sHookLock = nil;
static NSMutableSet<NSValue*>* sTeakHookIMPs = nil;

static void TeakSceneHooksInitRegistry(void) {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sHookLock = [[NSObject alloc] init];
    sTeakHookIMPs = [[NSMutableSet alloc] init];
  });
}

// Returns YES for the outermost Teak hook of this selector on this thread.
static BOOL TeakSceneHookEnter(SEL sel) {
  NSMutableDictionary* threadDictionary = [[NSThread currentThread] threadDictionary];
  NSString* key = [@"io.teak.sdk.sceneHookDepth." stringByAppendingString:NSStringFromSelector(sel)];
  NSInteger depth = [threadDictionary[key] integerValue];
  threadDictionary[key] = @(depth + 1);
  return depth == 0;
}

static void TeakSceneHookExit(SEL sel) {
  NSMutableDictionary* threadDictionary = [[NSThread currentThread] threadDictionary];
  NSString* key = [@"io.teak.sdk.sceneHookDepth." stringByAppendingString:NSStringFromSelector(sel)];
  NSInteger depth = [threadDictionary[key] integerValue] - 1;
  if (depth > 0) {
    threadDictionary[key] = @(depth);
  } else {
    [threadDictionary removeObjectForKey:key];
  }
}

#pragma mark - Teak handling

API_AVAILABLE(ios(13.0))
static BOOL TeakSceneOpenURLContext(UIOpenURLContext* context) {
  return [[Teak sharedInstance] application:[UIApplication sharedApplication] openURL:context.URL sourceApplication:context.options.sourceApplication annotation:context.options.annotation];
}

static void TeakSceneContinueUserActivity(NSUserActivity* activity) {
  [[Teak sharedInstance] application:[UIApplication sharedApplication] continueUserActivity:activity restorationHandler:^(NSArray* _arr){}];
}

API_AVAILABLE(ios(13.0))
static void TeakSceneHandleConnectionOptions(UISceneConnectionOptions* connectionOptions) {
  for (NSUserActivity* activity in connectionOptions.userActivities) {
    TeakSceneContinueUserActivity(activity);
  }
  for (UIOpenURLContext* context in connectionOptions.URLContexts) {
    TeakSceneOpenURLContext(context);
  }
}

#pragma mark - Hook factories

static void TeakSceneHookClass(Class klass, NSString* source, BOOL addContinueUserActivity);

// option: add scene:continueUserActivity: to delegates that lack it.
API_AVAILABLE(ios(13.0))
static IMP TeakConfigurationHook(SEL sel, IMP original, BOOL addContinueUserActivity) {
  TeakConfigurationIMP host = (TeakConfigurationIMP)original;
  return imp_implementationWithBlock(^UISceneConfiguration*(id self, UIApplication* application, UISceneSession* session, UISceneConnectionOptions* options) {
    UISceneConfiguration* configuration = host(self, sel, application, session, options);
    if (configuration.delegateClass != nil) {
      TeakSceneHookClass(configuration.delegateClass, @"configuration", addContinueUserActivity);
    }
    return configuration;
  });
}

API_AVAILABLE(ios(13.0))
static IMP TeakWillConnectHook(SEL sel, IMP original, BOOL unused) {
  TeakWillConnectIMP host = (TeakWillConnectIMP)original;
  return imp_implementationWithBlock(^(id self, UIScene* scene, UISceneSession* session, UISceneConnectionOptions* connectionOptions) {
    BOOL outermost = TeakSceneHookEnter(sel);
    if (host) {
      host(self, sel, scene, session, connectionOptions);
    }
    if (outermost) {
      TeakSceneHandleConnectionOptions(connectionOptions);
    }
    TeakSceneHookExit(sel);
  });
}

// option: forward contexts Teak handled to the host too.
API_AVAILABLE(ios(13.0))
static IMP TeakOpenURLContextsHook(SEL sel, IMP original, BOOL forwardTeakHandled) {
  TeakOpenURLContextsIMP host = (TeakOpenURLContextsIMP)original;
  return imp_implementationWithBlock(^(id self, UIScene* scene, NSSet<UIOpenURLContext*>* URLContexts) {
    BOOL outermost = TeakSceneHookEnter(sel);
    NSSet<UIOpenURLContext*>* forHost = URLContexts;
    if (outermost) {
      NSMutableSet<UIOpenURLContext*>* unhandled = [[NSMutableSet alloc] init];
      for (UIOpenURLContext* context in URLContexts) {
        if (!TeakSceneOpenURLContext(context)) {
          [unhandled addObject:context];
        }
      }
      if (!forwardTeakHandled) {
        forHost = unhandled;
      }
    }
    if (host && forHost.count > 0) {
      host(self, sel, scene, forHost);
    }
    TeakSceneHookExit(sel);
  });
}

API_AVAILABLE(ios(13.0))
static IMP TeakContinueUserActivityHook(SEL sel, IMP original, BOOL unused) {
  TeakContinueUserActivityIMP host = (TeakContinueUserActivityIMP)original;
  return imp_implementationWithBlock(^(id self, UIScene* scene, NSUserActivity* userActivity) {
    BOOL outermost = TeakSceneHookEnter(sel);
    if (host) {
      host(self, sel, scene, userActivity);
    }
    if (outermost) {
      TeakSceneContinueUserActivity(userActivity);
    }
    TeakSceneHookExit(sel);
  });
}

#pragma mark - Installing hooks

// Returns YES if the method was hooked.
static BOOL TeakSceneHookSelector(Class klass, SEL sel, Protocol* protocol, BOOL addWhenAbsent, TeakHookFactory factory, BOOL option) {
  TeakSceneHooksInitRegistry();
  @synchronized(sHookLock) {
    // Includes inherited implementations; an inherited one is the original this class forwards to.
    Method existing = class_getInstanceMethod(klass, sel);
    IMP original = existing ? method_getImplementation(existing) : NULL;

    // Already hooked here, or a hooked superclass's method inherited as-is.
    if (original != NULL && [sTeakHookIMPs containsObject:[NSValue valueWithPointer:(const void*)original]]) return NO;
    if (original == NULL && !addWhenAbsent) return NO;

    struct objc_method_description description = protocol_getMethodDescription(protocol, sel, NO, YES);
    const char* types = existing ? method_getTypeEncoding(existing) : description.types;
    if (types == NULL) return NO;

    IMP hook = factory(sel, original, option);
    [sTeakHookIMPs addObject:[NSValue valueWithPointer:(const void*)hook]];
    class_replaceMethod(klass, sel, hook, types);
    return YES;
  }
}

static void TeakSceneHookClass(Class klass, NSString* source, BOOL addContinueUserActivity) {
  if (klass == nil) return;
  if (@available(iOS 13, *)) {
    Protocol* sceneDelegate = objc_getProtocol("UISceneDelegate");
    Class swiftUISceneDelegate = objc_getClass("SwiftUI.AppSceneDelegate");
    BOOL forwardTeakHandled = swiftUISceneDelegate != nil && [klass isSubclassOfClass:swiftUISceneDelegate];
    BOOL hooked = NO;
    hooked |= TeakSceneHookSelector(klass, @selector(scene:willConnectToSession:options:), sceneDelegate, YES, TeakWillConnectHook, NO);
    hooked |= TeakSceneHookSelector(klass, @selector(scene:openURLContexts:), sceneDelegate, YES, TeakOpenURLContextsHook, forwardTeakHandled);
    hooked |= TeakSceneHookSelector(klass, @selector(scene:continueUserActivity:), sceneDelegate, addContinueUserActivity, TeakContinueUserActivityHook, NO);
    if (hooked) {
      TeakLog_i(@"sdk.init", @{@"scene_hooks" : NSStringFromClass(klass), @"source" : source});
    }
  }
}

+ (void)swizzleInto:(Class)klass {
  TeakSceneHookClass(klass, @"swizzleInto", NO);
}

+ (void)installForAppDelegateClass:(Class)appDelegateClass hostHandlesUserActivity:(BOOL)hostHandlesUserActivity {
  BOOL addContinueUserActivity = !hostHandlesUserActivity;

  // Scene delegate classes named in the Info.plist manifest, for every session role.
  NSDictionary* manifest = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UIApplicationSceneManifest"];
  NSDictionary* configurations = [manifest isKindOfClass:[NSDictionary class]] ? manifest[@"UISceneConfigurations"] : nil;
  if ([configurations isKindOfClass:[NSDictionary class]]) {
    for (id role in configurations) {
      NSArray* roleConfigurations = configurations[role];
      if (![roleConfigurations isKindOfClass:[NSArray class]]) continue;
      for (NSDictionary* config in roleConfigurations) {
        if (![config isKindOfClass:[NSDictionary class]]) continue;
        NSString* className = config[@"UISceneDelegateClassName"];
        if (![className isKindOfClass:[NSString class]]) continue;
        Class klass = NSClassFromString(className);
        if (klass == nil) {
          TeakLog_e(@"sdk.init", @{@"scene_hooks" : className, @"error" : @"class not found"});
          continue;
        }
        TeakSceneHookClass(klass, @"manifest", addContinueUserActivity);
      }
    }
  }

  // SwiftUI's App lifecycle scene delegate.
  TeakSceneHookClass(objc_getClass("SwiftUI.AppSceneDelegate"), @"swiftui", addContinueUserActivity);

  // Scene delegate classes chosen at runtime by the app delegate. Adding this method when it's absent
  // would change how UIKit resolves scene configurations.
  if (appDelegateClass != nil) {
    TeakSceneHookSelector(appDelegateClass, @selector(application:configurationForConnectingSceneSession:options:), objc_getProtocol("UIApplicationDelegate"), NO, TeakConfigurationHook, addContinueUserActivity);
  }

  // Anything else: hook the delegate of each scene as it connects. UIKit posts this after the
  // delegate's scene:willConnectToSession:options:, so it only catches later opens, not launch URLs.
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    [[NSNotificationCenter defaultCenter] addObserverForName:UISceneWillConnectNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification* notification) {
                                                    UIScene* scene = notification.object;
                                                    if (![scene isKindOfClass:[UIScene class]] || scene.delegate == nil) return;
                                                    TeakSceneHookClass([scene.delegate class], @"will_connect", addContinueUserActivity);
                                                  }];
  });
}

#pragma mark - Public methods
// For scene delegates that forward to Teak by hand.

- (void)scene:(UIScene*)scene willConnectToSession:(UISceneSession*)session options:(UISceneConnectionOptions*)connectionOptions {
  TeakSceneHandleConnectionOptions(connectionOptions);
}

- (void)scene:(UIScene*)scene continueUserActivity:(NSUserActivity*)userActivity {
  TeakSceneContinueUserActivity(userActivity);
}

- (void)scene:(UIScene*)scene openURLContexts:(NSSet<UIOpenURLContext*>*)URLContexts {
  for (UIOpenURLContext* context in URLContexts) {
    TeakSceneOpenURLContext(context);
  }
}

- (void)sceneWillResignActive:(UIScene*)scene {
  TeakLifecycleWillResignActive([UIApplication sharedApplication]);
}

- (void)sceneDidBecomeActive:(UIScene*)scene {
  TeakLifecycleDidBecomeActive([UIApplication sharedApplication]);
}

@end
