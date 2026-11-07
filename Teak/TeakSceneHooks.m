#import <objc/runtime.h>
#import <UIKit/UIKit.h>
#import "TeakSceneHooks.h"
#import <Teak/Teak.h>
#import "Teak+Internal.h"

// Scene delegates are hooked per class. Each hooked class keeps its own original implementations in
// sHostIMPs, so hooking several classes (UIKit + SwiftUI, a subclass and its superclass) or the same
// class twice never mixes up which original to call.
//
// UIKit does not fall back to the app delegate's openURL/continueUserActivity when the scene delegate
// doesn't implement the scene variants, so the link hooks are added when absent.

@interface TeakSceneHooks (Discovery)
+ (void)installForAppDelegateClass:(Class)appDelegateClass;
@end

@implementation TeakSceneHooks

static NSObject* sHookLock = nil;
// Class (pointer value) -> selector name -> original IMP (NSValue pointer), or NSNull when Teak
// added the method and there is no original to call.
static NSMutableDictionary<NSValue*, NSMutableDictionary<NSString*, id>*>* sHostIMPs = nil;

static void TeakSceneHooksInitRegistry(void) {
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sHookLock = [[NSObject alloc] init];
    sHostIMPs = [[NSMutableDictionary alloc] init];
  });
}

// Walks up from the receiver's class to the nearest class hooked for this selector. A subclass that
// inherits a hooked method from a hooked superclass has no entry of its own for that selector, so the
// walk continues to the superclass entry rather than stopping at the first hooked class.
API_AVAILABLE(ios(13.0))
static IMP TeakSceneHostIMP(id self, SEL sel) {
  TeakSceneHooksInitRegistry();
  NSString* selName = NSStringFromSelector(sel);
  @synchronized(sHookLock) {
    for (Class c = object_getClass(self); c != nil; c = class_getSuperclass(c)) {
      id entry = sHostIMPs[[NSValue valueWithPointer:(__bridge const void*)c]][selName];
      if (entry != nil) {
        return entry == [NSNull null] ? NULL : (IMP)[entry pointerValue];
      }
    }
  }
  return NULL;
}

// Caller holds sHookLock. Returns YES if the method was hooked.
API_AVAILABLE(ios(13.0))
static BOOL TeakSceneHookSelector(Class klass, SEL sel, BOOL addWhenAbsent) {
  Method teakMethod = class_getInstanceMethod([TeakSceneHooks class], sel);
  IMP teakIMP = method_getImplementation(teakMethod);

  // Includes inherited implementations; an inherited one is the original this class should forward to.
  Method existing = class_getInstanceMethod(klass, sel);
  IMP original = existing ? method_getImplementation(existing) : NULL;

  NSValue* classKey = [NSValue valueWithPointer:(__bridge const void*)klass];
  NSString* selName = NSStringFromSelector(sel);

  // Already hooked on this class, or a hooked superclass's method is inherited as-is.
  if (sHostIMPs[classKey][selName] != nil) return NO;
  if (original == teakIMP) return NO;
  if (original == NULL && !addWhenAbsent) return NO;

  NSMutableDictionary* classIMPs = sHostIMPs[classKey];
  if (classIMPs == nil) {
    classIMPs = [[NSMutableDictionary alloc] init];
    sHostIMPs[classKey] = classIMPs;
  }
  classIMPs[selName] = original ? [NSValue valueWithPointer:(const void*)original] : [NSNull null];
  class_replaceMethod(klass, sel, teakIMP, method_getTypeEncoding(teakMethod));
  return YES;
}

API_AVAILABLE(ios(13.0))
static void TeakSceneHookClass(Class klass, NSArray<NSString*>* selectorNames, NSString* source) {
  if (klass == nil) return;
  TeakSceneHooksInitRegistry();

  BOOL hookedAny = NO;
  @synchronized(sHookLock) {
    for (NSString* selName in selectorNames) {
      hookedAny |= TeakSceneHookSelector(klass, NSSelectorFromString(selName), YES);
    }
  }

  if (hookedAny) {
    TeakLog_i(@"sdk.init", @{@"scene_hooks" : NSStringFromClass(klass), @"source" : source});
  }
}

static NSArray<NSString*>* TeakSceneDelegateSelectors(void) {
  return @[ @"scene:willConnectToSession:options:", @"scene:openURLContexts:", @"scene:continueUserActivity:" ];
}

+ (void)swizzleInto:(Class)klass {
  TeakSceneHookClass(klass, TeakSceneDelegateSelectors(), @"swizzleInto");
}

+ (void)installForAppDelegateClass:(Class)appDelegateClass {
  TeakSceneHooksInitRegistry();

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
        TeakSceneHookClass(klass, TeakSceneDelegateSelectors(), @"manifest");
      }
    }
  }

  // SwiftUI's App lifecycle scene delegate.
  TeakSceneHookClass(objc_getClass("SwiftUI.AppSceneDelegate"), TeakSceneDelegateSelectors(), @"swiftui");

  // Scene delegate classes chosen at runtime by the app delegate. Only wrapped when the app delegate
  // implements it; adding it would change how UIKit resolves scene configurations.
  if (appDelegateClass != nil && class_respondsToSelector(appDelegateClass, @selector(application:configurationForConnectingSceneSession:options:))) {
    @synchronized(sHookLock) {
      TeakSceneHookSelector(appDelegateClass, @selector(application:configurationForConnectingSceneSession:options:), NO);
    }
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
                                                    TeakSceneHookClass([scene.delegate class], TeakSceneDelegateSelectors(), @"will_connect");
                                                  }];
  });
}

#pragma mark - Hooks

- (UISceneConfiguration*)application:(UIApplication*)application configurationForConnectingSceneSession:(UISceneSession*)session options:(UISceneConnectionOptions*)options {
  UISceneConfiguration* (*host)(id, SEL, UIApplication*, UISceneSession*, UISceneConnectionOptions*) =
      (UISceneConfiguration * (*)(id, SEL, UIApplication*, UISceneSession*, UISceneConnectionOptions*)) TeakSceneHostIMP(self, _cmd);
  UISceneConfiguration* configuration = host ? host(self, _cmd, application, session, options) : session.configuration;
  if (configuration.delegateClass != nil) {
    TeakSceneHookClass(configuration.delegateClass, TeakSceneDelegateSelectors(), @"configuration");
  }
  return configuration;
}

- (void)scene:(UIScene*)scene willConnectToSession:(UISceneSession*)session options:(UISceneConnectionOptions*)connectionOptions {
  void (*host)(id, SEL, UIScene*, UISceneSession*, UISceneConnectionOptions*) =
      (void (*)(id, SEL, UIScene*, UISceneSession*, UISceneConnectionOptions*))TeakSceneHostIMP(self, _cmd);
  if (host) {
    host(self, _cmd, scene, session, connectionOptions);
  }

  for (NSUserActivity* activity in connectionOptions.userActivities) {
    [[Teak sharedInstance] application:[UIApplication sharedApplication] continueUserActivity:activity restorationHandler:^(NSArray* _arr){}];
  }

  for (UIOpenURLContext* context in connectionOptions.URLContexts) {
    [[Teak sharedInstance] application:[UIApplication sharedApplication] openURL:context.URL sourceApplication:context.options.sourceApplication annotation:context.options.annotation];
  }
}

- (void)scene:(UIScene*)scene continueUserActivity:(NSUserActivity*)userActivity {
  void (*host)(id, SEL, UIScene*, NSUserActivity*) = (void (*)(id, SEL, UIScene*, NSUserActivity*))TeakSceneHostIMP(self, _cmd);
  if (host) {
    host(self, _cmd, scene, userActivity);
  }
  [[Teak sharedInstance] application:[UIApplication sharedApplication] continueUserActivity:userActivity restorationHandler:^(NSArray* _arr){}];
}

- (void)scene:(UIScene*)scene openURLContexts:(NSSet<UIOpenURLContext*>*)URLContexts {
  for (UIOpenURLContext* context in URLContexts) {
    [[Teak sharedInstance] application:[UIApplication sharedApplication] openURL:context.URL sourceApplication:context.options.sourceApplication annotation:context.options.annotation];
  }

  void (*host)(id, SEL, UIScene*, NSSet<UIOpenURLContext*>*) = (void (*)(id, SEL, UIScene*, NSSet<UIOpenURLContext*>*))TeakSceneHostIMP(self, _cmd);
  if (host) {
    host(self, _cmd, scene, URLContexts);
  }
}

// Lifecycle comes from UIApplication notifications (see Teak_Plant); these are no longer installed
// on scene delegates.
- (void)sceneWillResignActive:(UIScene*)scene {
  [[Teak sharedInstance] applicationWillResignActive:[UIApplication sharedApplication]];
}

- (void)sceneDidBecomeActive:(UIScene*)scene {
  [[Teak sharedInstance] applicationDidBecomeActive:[UIApplication sharedApplication]];
}

@end
