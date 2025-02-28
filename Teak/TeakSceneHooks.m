#import <objc/runtime.h>
#import <UIKit/UIScene.h>
#import "TeakSceneHooks.h"

// @interface TeakSceneHooks : NSObject

// - (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions;
// - (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)userActivity;
// - (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts;

// - (void)sceneWillResignActive:(UIScene *)scene;
// - (void)sceneDidBecomeActive:(UIScene *)scene;
// - (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts;

// +(void)swizzleInto:(Class)klass
// @end

@implementation TeakSceneHooks

static SEL sceneDBA = NULL;
static void (*sHostSceneDBA)(id, SEL, UIScene*) = NULL;

static SEL sceneWRA = NULL;
static void (*sHostSceneWRA)(id, SEL, UIScene*) = NULL;

static SEL sceneOpenURLContexts = NULL;
static void (*sHostSceneOpenURLContexts)(id, SEL, UIScene*, NSSet<UIOpenURLContext *>*) = NULL;

static SEL sceneWCTS = NULL;
static void (*sHostSceneWCTS)(id, SEL, UIScene*, UISceneSession*, UISceneConnectionOptions*) = NULL;

static SEL sceneCUA = NULL;
static void (*sHostSceneCUA)(id, SEL, UIScene*, NSUserActivity*) = NULL;

static Protocol* uiSceneDelegateProto = NULL;

static void* swizzleMethod(Class klass, SEL sel) {
  if (class_respondsToSelector(klass, sel)) {
    struct objc_method_description desc = protocol_getMethodDescription(uiSceneDelegateProto, sel, NO, YES);
    Method m = class_getInstanceMethod([TeakSceneHooks class], desc.name);
    return class_replaceMethod(klass, desc.name, method_getImplementation(m), desc.types);
  } else {
    return NULL;
  }
}

+(void)swizzleInto:(Class)klass {
  uiSceneDelegateProto = objc_getProtocol("UISceneDelegate");

  sceneDBA = @selector(sceneDidBecomeActive:);
  sHostSceneDBA = swizzleMethod(klass, sceneDBA);

  sceneWRA = @selector(sceneWillResignActive:);
  sHostSceneWRA = swizzleMethod(klass, sceneWRA);

  sceneOpenURLContexts = @selector(scene:openURLContexts:);
  sHostSceneOpenURLContexts = swizzleMethod(klass, sceneOpenURLContexts);

  sceneWCTS = @selector(scene:willConnectToSession:options:);
  sHostSceneWCTS = swizzleMethod(klass, sceneWCTS);

  sceneCUA = @selector(scene:continueUserActivity:);
  sHostSceneCUA = swizzleMethod(klass, sceneCUA);
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions;
{
  if(sHostSceneWCTS) {
    sHostSceneWCTS(self, sceneWCTS, scene, session, connectionOptions);
  }
}

- (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)userActivity;
{
  if(sHostSceneCUA) {
    sHostSceneCUA(self, sceneCUA, scene, userActivity);
  }
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts;
{
  if(sHostSceneOpenURLContexts) {
    sHostSceneOpenURLContexts(self, sceneOpenURLContexts, scene, URLContexts);
  }
}

- (void)sceneWillResignActive:(UIScene *)scene;
{
  if(sHostSceneWRA) {
    sHostSceneWRA(self, sceneWRA, scene);
  }
}

- (void)sceneDidBecomeActive:(UIScene *)scene;
{
  if(sHostSceneDBA) {
    sHostSceneDBA(self, sceneDBA, scene);
  }
}

@end
