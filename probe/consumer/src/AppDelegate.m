#import "AppDelegate.h"
#import <Teak/Teak.h>

extern BOOL TeakRequestPushAuthorization(BOOL includeProvisional);

@implementation AppDelegate
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  NSLog(@"PROBE: didFinishLaunching");
  [[NSNotificationCenter defaultCenter] addObserverForName:TeakOnReward object:nil queue:nil usingBlock:^(NSNotification* n) { NSLog(@"PROBE: TeakOnReward %@", n.userInfo); }];
  [[Teak sharedInstance] identifyUser:@"c-2181-probe"];
  // Provisional auth: no prompt, so the sim can receive a push unattended.
  NSLog(@"PROBE: TeakRequestPushAuthorization -> %d", TeakRequestPushAuthorization(YES));
  if (@available(iOS 13.0, *)) {
    if ([[NSBundle mainBundle] objectForInfoDictionaryKey:@"UIApplicationSceneManifest"] != nil) return YES;
  }
  self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  self.window.rootViewController = [[UIViewController alloc] init];
  [self.window makeKeyAndVisible];
  return YES;
}
- (void)applicationDidBecomeActive:(UIApplication*)application {
  NSLog(@"PROBE: applicationDidBecomeActive");
}
- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken {
  NSLog(@"PROBE: app delegate got push token (%lu bytes)", (unsigned long)deviceToken.length);
}
- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error {
  NSLog(@"PROBE: push registration failed %@", error);
}
@end
