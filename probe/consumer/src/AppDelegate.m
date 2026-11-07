#import "AppDelegate.h"
#import <Teak/Teak.h>

extern BOOL TeakRequestPushAuthorization(BOOL includeProvisional);
extern BOOL TeakOpenSettingsAppToThisAppsSettings(void);

@implementation AppDelegate
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  NSLog(@"PROBE: didFinishLaunching");
  [[NSNotificationCenter defaultCenter] addObserverForName:TeakOnReward object:nil queue:nil usingBlock:^(NSNotification* n) { NSLog(@"PROBE: TeakOnReward %@", n.userInfo); }];
  [[Teak sharedInstance] identifyUser:@"c-2181-probe"];
  // Provisional auth: no prompt, so the sim can receive a push unattended.
  NSLog(@"PROBE: TeakRequestPushAuthorization -> %d", TeakRequestPushAuthorization(YES));
  [AppDelegate probeOpenSettingsAfterDelay];
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
+ (void)probeOpenSettingsAfterDelay {
  // Teak's open-settings helper; a working call backgrounds the app into Settings.
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
    NSLog(@"PROBE: openSettings -> %d", TeakOpenSettingsAppToThisAppsSettings());
  });
}
- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken {
  NSLog(@"PROBE: app delegate got push token (%lu bytes)", (unsigned long)deviceToken.length);
}
- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error {
  NSLog(@"PROBE: push registration failed %@", error);
}
@end
