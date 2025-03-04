#import <objc/runtime.h>
#import <UIKit/UIScene.h>

API_AVAILABLE(ios(13))
@interface TeakSceneHooks : NSObject

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions;
- (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)userActivity;
- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts;

- (void)sceneWillResignActive:(UIScene *)scene;
- (void)sceneDidBecomeActive:(UIScene *)scene;

+(void)swizzleInto:(Class)klass;
@end
