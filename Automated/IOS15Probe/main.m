#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import "probe.h"

__attribute__((constructor)) static void app_ctor(void) { ProbeScreen("A:constructor-in-app-binary", "A"); }

@interface LoadProbe : NSObject @end
@implementation LoadProbe
+ (void)load { ProbeScreen("C:+load", "C"); }
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate> @property (strong) UIWindow* window; @end
@implementation AppDelegate
- (BOOL)application:(UIApplication*)a didFinishLaunchingWithOptions:(NSDictionary*)o {
  ProbeScreen("E:didFinishLaunching", "E");
  dispatch_async(dispatch_get_global_queue(0, 0), ^{ ProbeScreen("F:background-thread-after-launch", "F"); });
#ifdef PROBE_DLOPEN_G
  dispatch_async(dispatch_get_global_queue(0, 0), ^{
    NSString* p = [[NSBundle mainBundle].bundlePath stringByAppendingPathComponent:@"Frameworks/libprobe_dl.dylib"];
    void* h = dlopen(p.UTF8String, RTLD_NOW);
    PLOG("dlopen G -> %p %{public}s", h, h ? "" : dlerror());
  });
#endif
  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  self.window.rootViewController = [UIViewController new];
  [self.window makeKeyAndVisible];
  PLOG("DONE launch");
  return YES;
}
@end

int main(int argc, char* argv[]) {
  ProbeScreen("D:main-before-UIApplicationMain", "D");
  ProbeScreen("H:control-deliberate-stall", "H");
  @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class])); }
}
