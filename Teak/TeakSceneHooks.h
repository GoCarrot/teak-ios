#import <objc/runtime.h>
#import <UIKit/UIScene.h>

@interface TeakSceneHooks : NSObject

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions;
- (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)userActivity;
- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts;

- (void)sceneWillResignActive:(UIScene *)scene;
- (void)sceneDidBecomeActive:(UIScene *)scene;
- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts;

+(void)swizzleInto:(Class)klass;
@end
