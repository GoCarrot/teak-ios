#import "SceneDelegate.h"

@implementation SceneDelegate
- (void)scene:(UIScene*)scene willConnectToSession:(UISceneSession*)session options:(UISceneConnectionOptions*)connectionOptions {
  NSLog(@"PROBE: scene willConnect");
  self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene*)scene];
  self.window.rootViewController = [[UIViewController alloc] init];
  [self.window makeKeyAndVisible];
}
- (void)sceneDidBecomeActive:(UIScene*)scene {
  NSLog(@"PROBE: sceneDidBecomeActive");
}
@end
