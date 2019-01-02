#import "LifecycleEvent.h"

@implementation LifecycleEvent
+ (void)applicationFinishedLaunching {
  LifecycleEvent* event = [[LifecycleEvent alloc] initWithType:LifecycleFinishedLaunching];
  [TeakEvent postEvent:event];
}

+ (void)applicationActivate {
  LifecycleEvent* event = [[LifecycleEvent alloc] initWithType:LifecycleActivate];
  [TeakEvent postEvent:event];
}

+ (void)applicationDeactivate {
  LifecycleEvent* event = [[LifecycleEvent alloc] initWithType:LifecycleDeactivate];
  [TeakEvent postEvent:event];
}
@end
