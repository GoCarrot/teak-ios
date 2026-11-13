// Probe only. See SK2Observer.h.
#import "SK2Observer.h"
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <objc/runtime.h>
#import <sys/mman.h>

#define SWIFTCALL __attribute__((swiftcall))
#define SWIFTASYNCCALL __attribute__((swiftasynccall))
#define SWIFT_CONTEXT __attribute__((swift_context))
#define SWIFT_ASYNC_CONTEXT __attribute__((swift_async_context))

static void olog(NSString *s) {
  NSString *path = NSProcessInfo.processInfo.environment[@"PROBE_LOG"] ?: @"/tmp/storekit-probe.log";
  NSString *line = [NSString stringWithFormat:@"PROBE [objc] %@\n", s];
  NSLog(@"%@", line);
  NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
  if (h) {
    [h seekToEndOfFile];
    [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
  } else {
    [line writeToFile:path atomically:NO encoding:NSUTF8StringEncoding error:nil];
  }
}

// Swift async function pointer record: relative offset to the entry point, initial context size.
typedef struct {
  int32_t function;
  uint32_t contextSize;
} SwiftAsyncFunctionPointer;

typedef SWIFTASYNCCALL void (*FinishFn)(SWIFT_ASYNC_CONTEXT void *ctx, SWIFT_CONTEXT void *selfp);
typedef SWIFTCALL uint64_t (*U64GetterFn)(SWIFT_CONTEXT void *selfp);
typedef struct {
  uint64_t a, b;
} SwiftPair;
typedef SWIFTCALL SwiftPair (*DataGetterFn)(SWIFT_CONTEXT void *selfp);
typedef SWIFTCALL id (*DataBridgeFn)(uint64_t a, uint64_t b);

static FinishFn sOrigFinish;
static U64GetterFn sGetId;
static DataGetterFn sGetJSON;
static DataBridgeFn sBridgeData;
static SwiftAsyncFunctionPointer sHookAFP;
static NSMutableArray<NSNumber *> *sIds;
static NSMutableArray<NSString *> *sJSON;

// Is this transaction in the app receipt at finish time? Counts the ASCII id inside the PKCS7 blob,
// so no ASN.1 parsing; a count of 0 with bytes>0 means the receipt doesn't carry it (yet).
static NSString *receiptInfo(uint64_t txid) {
  NSURL *url = NSBundle.mainBundle.appStoreReceiptURL;
  NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
  if (!data) return [NSString stringWithFormat:@"missing(%@)", url.lastPathComponent];
  NSData *needle = [[NSString stringWithFormat:@"%llu", txid] dataUsingEncoding:NSUTF8StringEncoding];
  NSUInteger count = 0;
  NSRange r = NSMakeRange(0, data.length);
  while (true) {
    NSRange f = [data rangeOfData:needle options:0 range:r];
    if (f.location == NSNotFound) break;
    count++;
    r = NSMakeRange(NSMaxRange(f), data.length - NSMaxRange(f));
  }
  return [NSString stringWithFormat:@"bytes=%lu txIdOccurrences=%lu", (unsigned long)data.length, (unsigned long)count];
}

// Kept out of the thunk: ARC cleanups in the thunk's scope would block the musttail call.
__attribute__((noinline)) static void recordFinish(void *selfp) {
  uint64_t txid = sGetId ? sGetId(selfp) : 0;
  NSString *json = @"(no json getter)";
  if (sGetJSON && sBridgeData && getenv("PROBE_SKIP_JSON") == NULL) {
    SwiftPair d = sGetJSON(selfp);
    NSData *data = sBridgeData(d.a, d.b);
    json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"(not utf8)";
  }
  @synchronized(sIds) {
    [sIds addObject:@(txid)];
    [sJSON addObject:json];
  }
  olog([NSString stringWithFormat:@"finish thunk: Transaction.id=%llu receipt=%@ json=%@", txid, receiptInfo(txid), json]);
}

static SWIFTASYNCCALL void finishThunk(SWIFT_ASYNC_CONTEXT void *ctx, SWIFT_CONTEXT void *selfp) {
  recordFinish(selfp);
  __attribute__((musttail)) return sOrigFinish(ctx, selfp);
}

static NSInteger rebindSlotsInImage(const struct mach_header_64 *mh, intptr_t slide, void *target, void *replacement) {
  NSInteger n = 0;
  const uint8_t *cmd = (const uint8_t *)(mh + 1);
  for (uint32_t i = 0; i < mh->ncmds; i++, cmd += ((const struct load_command *)cmd)->cmdsize) {
    const struct load_command *lc = (const struct load_command *)cmd;
    if (lc->cmd != LC_SEGMENT_64) continue;
    const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
    if (strncmp(seg->segname, "__DATA", 6) != 0 && strncmp(seg->segname, "__AUTH", 6) != 0) continue;
    const struct section_64 *sect = (const struct section_64 *)(seg + 1);
    for (uint32_t s = 0; s < seg->nsects; s++, sect++) {
      uint32_t type = sect->flags & SECTION_TYPE;
      if (type != S_NON_LAZY_SYMBOL_POINTERS && type != S_LAZY_SYMBOL_POINTERS) continue;
      void **slots = (void **)(sect->addr + slide);
      size_t count = sect->size / sizeof(void *);
      for (size_t k = 0; k < count; k++) {
        if (slots[k] != target) continue;
        uintptr_t page = (uintptr_t)&slots[k] & ~(uintptr_t)(PAGE_SIZE - 1);
        kern_return_t kr = vm_protect(mach_task_self(), page, PAGE_SIZE, false, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
        if (kr != KERN_SUCCESS) {
          olog([NSString stringWithFormat:@"vm_protect failed %d in %s,%s", kr, seg->segname, sect->sectname]);
          continue;
        }
        slots[k] = replacement;
        vm_protect(mach_task_self(), page, PAGE_SIZE, false, VM_PROT_READ);
        n++;
      }
    }
  }
  return n;
}

// VerificationResult<Transaction>.jwsRepresentation getter: self indirect in the context register,
// String returned in two registers. Wrapping it sees the JWS of every transaction the app reads one for.
typedef SWIFTCALL SwiftPair (*JWSGetterFn)(SWIFT_CONTEXT void *selfp);
typedef SWIFTCALL id (*StringBridgeFn)(uint64_t a, uint64_t b);
static JWSGetterFn sOrigJWS;
static StringBridgeFn sBridgeString;
static NSMutableArray<NSString *> *sJWS;

__attribute__((noinline)) static void recordJWS(SwiftPair str) {
  NSString *jws = sBridgeString ? sBridgeString(str.a, str.b) : @"(no bridge)";
  @synchronized(sJWS) {
    [sJWS addObject:jws];
  }
  olog([NSString stringWithFormat:@"jws thunk: length=%lu prefix=%@", (unsigned long)jws.length, [jws substringToIndex:MIN(jws.length, (NSUInteger)40)]]);
}

static SWIFTCALL SwiftPair jwsThunk(SWIFT_CONTEXT void *selfp) {
  SwiftPair r = sOrigJWS(selfp);
  recordJWS(r);
  return r;
}

static NSInteger rebindEverywhere(void *target, void *replacement, const char *what) {
  NSInteger total = 0;
  for (uint32_t i = 0; i < _dyld_image_count(); i++) {
    NSInteger n = rebindSlotsInImage((const struct mach_header_64 *)_dyld_get_image_header(i), _dyld_get_image_vmaddr_slide(i), target, replacement);
    if (n) olog([NSString stringWithFormat:@"hook: rebound %s %ld slot(s) in %s", what, (long)n, _dyld_get_image_name(i)]);
    total += n;
  }
  return total;
}

@implementation SK2Observer

+ (NSInteger)installJWSHook {
  sJWS = [NSMutableArray array];
  sOrigJWS = (JWSGetterFn)dlsym(RTLD_DEFAULT, "$s8StoreKit18VerificationResultOA2A11TransactionVRszlE17jwsRepresentationSSvg");
  sBridgeString = (StringBridgeFn)dlsym(RTLD_DEFAULT, "$sSS10FoundationE19_bridgeToObjectiveCSo8NSStringCyF");
  if (!sOrigJWS || !sBridgeString) {
    olog([NSString stringWithFormat:@"jws hook: missing symbols getter=%p bridge=%p", sOrigJWS, sBridgeString]);
    return 0;
  }
  NSInteger n = rebindEverywhere((void *)sOrigJWS, (void *)jwsThunk, "jws");
  olog([NSString stringWithFormat:@"jws hook: total rebound=%ld", (long)n]);
  return n;
}

+ (NSArray<NSString *> *)seenJWS {
  @synchronized(sJWS) {
    return [sJWS copy];
  }
}

+ (void)dumpStoreKitRuntime {
  Dl_info info;
  void *sym = dlsym(RTLD_DEFAULT, "$s8StoreKit11TransactionV2ids6UInt64Vvg");
  if (!sym || !dladdr(sym, &info)) {
    olog(@"dump: StoreKit not found");
    return;
  }
  unsigned int count = 0;
  const char **names = objc_copyClassNamesForImage(info.dli_fname, &count);
  NSMutableArray *all = [NSMutableArray array];
  for (unsigned int i = 0; i < count; i++) [all addObject:@(names[i])];
  free(names);
  [all sortUsingSelector:@selector(compare:)];
  olog([NSString stringWithFormat:@"dump: %u ObjC classes in %s", count, info.dli_fname]);
  olog([NSString stringWithFormat:@"dump: classes=%@", [all componentsJoinedByString:@","]]);

  NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(?i)transaction|purchase|finish|receipt|unfinished|entitlement" options:0 error:nil];
  for (NSString *cn in all) {
    Class cls = NSClassFromString(cn);
    if (!cls) continue;
    unsigned int mc = 0;
    Method *ms = class_copyMethodList(cls, &mc);
    NSMutableArray *hits = [NSMutableArray array];
    for (unsigned int m = 0; m < mc; m++) {
      NSString *sel = NSStringFromSelector(method_getName(ms[m]));
      if ([re firstMatchInString:sel options:0 range:NSMakeRange(0, sel.length)]) [hits addObject:sel];
    }
    free(ms);
    if (hits.count) olog([NSString stringWithFormat:@"dump: %@ -%@", cn, [hits componentsJoinedByString:@" -"]]);
  }

  unsigned int pc = 0;
  Protocol *__unsafe_unretained *ps = objc_copyProtocolList(&pc);
  for (unsigned int i = 0; i < pc; i++) {
    NSString *pn = @(protocol_getName(ps[i]));
    if (![re firstMatchInString:pn options:0 range:NSMakeRange(0, pn.length)] && ![pn containsString:@"SK"] && ![pn containsString:@"ASD"]) continue;
    unsigned int dc = 0;
    struct objc_method_description *ds = protocol_copyMethodDescriptionList(ps[i], YES, YES, &dc);
    NSMutableArray *sels = [NSMutableArray array];
    for (unsigned int d = 0; d < dc; d++) [sels addObject:NSStringFromSelector(ds[d].name)];
    free(ds);
    olog([NSString stringWithFormat:@"dump: protocol %@ {%@}", pn, [sels componentsJoinedByString:@" "]]);
  }
  free(ps);
}

+ (NSInteger)installFinishHook {
  sIds = [NSMutableArray array];
  sJSON = [NSMutableArray array];
  SwiftAsyncFunctionPointer *afp = dlsym(RTLD_DEFAULT, "$s8StoreKit11TransactionV6finishyyYaFTu");
  sGetId = (U64GetterFn)dlsym(RTLD_DEFAULT, "$s8StoreKit11TransactionV2ids6UInt64Vvg");
  sGetJSON = (DataGetterFn)dlsym(RTLD_DEFAULT, "$s8StoreKit11TransactionV18jsonRepresentation10Foundation4DataVvg");
  sBridgeData = (DataBridgeFn)dlsym(RTLD_DEFAULT, "$s10Foundation4DataV19_bridgeToObjectiveCSo6NSDataCyF");
  if (!afp || !sGetId) {
    olog([NSString stringWithFormat:@"hook: missing symbols afp=%p id=%p", afp, sGetId]);
    return 0;
  }
  sOrigFinish = (FinishFn)((intptr_t)&afp->function + afp->function);
  sHookAFP.contextSize = afp->contextSize;
  sHookAFP.function = (int32_t)((intptr_t)finishThunk - (intptr_t)&sHookAFP.function);
  NSInteger total = 0;
  for (uint32_t i = 0; i < _dyld_image_count(); i++) {
    const struct mach_header_64 *mh = (const struct mach_header_64 *)_dyld_get_image_header(i);
    // Swift callers bind both: the async function pointer (for the context size) and the entry
    // point itself, which they call through the GOT. Rebind both.
    intptr_t slide = _dyld_get_image_vmaddr_slide(i);
    NSInteger nAFP = rebindSlotsInImage(mh, slide, afp, &sHookAFP);
    NSInteger nFn = rebindSlotsInImage(mh, slide, (void *)sOrigFinish, (void *)finishThunk);
    if (nAFP || nFn) olog([NSString stringWithFormat:@"hook: rebound afp=%ld fn=%ld slot(s) in %s", (long)nAFP, (long)nFn, _dyld_get_image_name(i)]);
    total += nAFP + nFn;
  }
  olog([NSString stringWithFormat:@"hook: finish afp=%p orig=%p ctxSize=%u total rebound=%ld json=%s", afp, sOrigFinish, afp->contextSize, (long)total, sGetJSON && sBridgeData ? "yes" : "no"]);
  return total;
}

+ (NSArray<NSNumber *> *)finishedIds {
  @synchronized(sIds) {
    return [sIds copy];
  }
}

+ (NSArray<NSString *> *)finishedJSON {
  @synchronized(sIds) {
    return [sJSON copy];
  }
}

+ (void)reset {
  @synchronized(sIds) {
    [sIds removeAllObjects];
    [sJSON removeAllObjects];
  }
}

@end
