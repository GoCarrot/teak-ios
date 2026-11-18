#import "probe.h"
__attribute__((constructor)) static void libprobe_dl_ctor(void) { ProbeScreen("G:constructor-in-dlopen-from-bg-thread", "G"); }
