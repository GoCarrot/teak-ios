#import "TeakEvent.h"

@interface LifecycleEvent : TeakEvent
+ (void)applicationFinishedLaunching;
+ (void)applicationActivate;
+ (void)applicationDeactivate;
@end
