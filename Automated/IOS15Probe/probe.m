#import <UIKit/UIKit.h>
#import <pthread.h>
#import <stdlib.h>
#import "probe.h"

// The case this binary runs, fixed at build time (-DPROBE_CASE='"A"'). A tapped launch carries no
// environment, and reading an Info.plist key would touch the main bundle, which is part of what
// is being probed.
#ifndef PROBE_CASE
#define PROBE_CASE "A"
#endif

static volatile int gDone = 0;
static void* watchdog(void* arg) {
  const char* where = (const char*)arg;
  sleep(5);
  if (gDone) return NULL;
  PLOG("RESULT %{public}s: HANG (call did not return in 5s)", where);
  return NULL;
}

void ProbeScreen(const char* where, const char* wantCase) {
  if (strcmp(PROBE_CASE, wantCase) != 0) return;
  // Logged before any main-bundle access so a hang there is distinguishable from a hang in UIScreen.
  PLOG("PRE0 %{public}s main=%d pthread=%p", where, [NSThread isMainThread], pthread_self());
  PLOG("PRE1 %{public}s bundle=%{public}s", where, [[[NSBundle mainBundle] bundleIdentifier] UTF8String] ?: "(nil)");
  pthread_t wd;
  pthread_create(&wd, NULL, watchdog, (void*)where);
  pthread_detach(wd);
  gDone = 0;
  if (!strcmp(wantCase, "H")) { sleep(30); } // control: deliberate stall, the watchdog must report HANG
  UIScreen* s = [UIScreen mainScreen];
  CGRect b = [s bounds];
  CGFloat sc = [s scale];
  gDone = 1;
  PLOG("RESULT %{public}s: ok bounds=%.0fx%.0f scale=%.1f main=%d pthread=%p", where, b.size.width, b.size.height, sc,
       [NSThread isMainThread], pthread_self());
}
