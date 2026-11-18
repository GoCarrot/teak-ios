#import "probe.h"
__attribute__((constructor)) static void libprobe_ctor(void) { ProbeScreen("B:constructor-in-linked-dylib", "B"); }
