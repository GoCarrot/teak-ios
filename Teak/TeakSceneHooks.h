#import <objc/runtime.h>
#import <UIKit/UIScene.h>
#import <UIKit/UIOpenURLContext.h>

API_AVAILABLE(ios(13))
@interface TeakSceneHooks : NSObject

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions;
- (void)scene:(UIScene *)scene continueUserActivity:(NSUserActivity *)userActivity;
- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts;

- (void)sceneWillResignActive:(UIScene *)scene;
- (void)sceneDidBecomeActive:(UIScene *)scene;

+(void)swizzleInto:(Class)klass;
@end

API_AVAILABLE(ios(13))
@interface UIOpenURLContext (Teak)

/**
 * YES if Teak handled this URL before passing it to your scene delegate's
 * @c scene:openURLContexts:.
 *
 * Scene delegates get every URL context, including Teak's. Check this to skip the
 * links Teak already handled. It's always NO for the URL contexts in the
 * connection options passed to @c scene:willConnectToSession:options:.
 */
@property (nonatomic, readonly) BOOL teakHandled;

@end
