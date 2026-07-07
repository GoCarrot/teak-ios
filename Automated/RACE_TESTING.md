# Race-condition testing

How to write a test that actually catches a given concurrency bug in this SDK, and how to prove the
test is trustworthy. Methodology first: the right detector depends on what kind of shared state is
racing, so start by classifying that.

## 1. Classify the shared state first

The detector that will actually fire depends on what's being shared. Three cases cover almost
everything here:

- **Immortal scalar or pointer** — the slot is written concurrently but the pointee is never freed
  (e.g. a state-machine field that only ever points at long-lived singletons). On arm64 an aligned
  load/store can't tear, so the race is formal (undefined behavior) but won't misbehave observably.
  A static "is this declared atomic?" assertion is the deterministic guard.
- **Strong pointer whose pointee CAN be freed concurrently** — a `nonatomic` strong property
  reassigned on one thread while another reads it (e.g. `TeakSession.serverSessionId`). Aligned-load
  atomicity stops a torn pointer, but not use-after-free: the reader loads the pointer, the writer's
  setter releases and frees the old object, and the reader then retains and dereferences freed
  memory. This is the dangerous case — and, as §2 shows, the one ThreadSanitizer is blind to.
- **Mutable container** — an `NSMutableDictionary` / `NSMutableArray` mutated on two threads at once
  (e.g. the `userProfile` string-attributes dict). The container's internal backing buffer
  reallocates on mutation, so a concurrent access touches freed/moved memory. Atomicity of the
  pointer to the container does nothing here; the access itself must be serialized.

The class tells you which tool below will fire — and, just as important, which will stay silent
while the bug is still there.

## The revert check (trustworthiness gate)

**A race test you haven't watched fail is not yet a test.** Every technique below — TSan test,
dynamic crash repro, static assertion — is only trustworthy once you have:

1. seen it **RED** with the bug present (fix reverted or not yet applied), and
2. seen it **GREEN** with the fix in place.

A test that stays green when you revert the fix guards nothing — it will stay green when the bug
comes back, too. Do the revert, watch the red, restore the fix, watch the green. Skip this and
you've written decoration, not a guard. This gate is non-negotiable, and it applies to all three
techniques equally.

## 2. ThreadSanitizer: what it catches, what it's blind to

TSan instruments memory accesses in first-party (Teak) code and reports when two threads touch the
same location without synchronization and at least one writes.

**It catches races where both sides are instrumented.** The mutable-container case is the sweet
spot: two threads mutating the same `NSMutableDictionary` both execute instrumented code, and TSan
reports `race on NSMutableDictionary`. Live template:
`testUserProfileAttributeDictIsSerializedUnderConcurrency` in
`Automated/AutomatedTests/RaceTripwireTests.m` drives the real attribute setter from two threads;
with the serialization fix it stays green, and reverting the fix (removing the operationQueue hop)
makes TSan fire. Open it as a starting point for a container-race test.

The mutate-vs-*enumerate* shape is caught just as reliably as two setters, and this was measured:
`testTeakLinkRouteRegistryIsSerializedUnderConcurrency` races the registry's `setObject:forKey:`
against a concurrent `countByEnumeratingWithState:`; reverting its `@synchronized` fired `race on
NSMutableDictionary` on 20/20 separate-process runs — effectively deterministic (a structural collision,
not a probabilistic sampling window). Both sides are instrumented
Foundation, so TSan pairs them — even though the write lands deep in CoreFoundation's dictionary
machinery. (Foundation's own "mutated while being enumerated" `NSGenericException` guard is the same
bug's off-TSan face — the production crash — but on the TSan lane the race report is what surfaces
first.) The lesson: reach for the container class in §1, not the load-bearing detail of two setters
vs. a setter-and-enumerator — any mutation concurrent with any access to the same container is the
sweet spot TSan sees.

**It is blind to the nonatomic-strong use-after-free.** For a `nonatomic` strong property, the
synthesized setter's store lands inside `objc_storeStrong` — libobjc, which is not instrumented.
TSan sees the reader's instrumented load of the ivar but never the writer's store, so it never pairs
them into a race and reports nothing. This was confirmed empirically against
`TeakSession.serverSessionId`: hammering the real setter and getter on two threads for hundreds of
thousands of iterations produced **zero** TSan output, even though the code is unambiguously racing
(see §3, where the same probe crashes hard).

> **Rule: a green TSan run does not mean "safe."** It clears the both-sides-instrumented classes
> (mutable containers, first-party field races). It says nothing about a nonatomic-strong pointer
> whose release lives in libobjc. Never read a green TSan as proof that a freeable-pointer property
> is race-free.

## 3. The dynamic crash repro (for the class TSan can't see)

The nonatomic-strong UAF has no TSan signal, but it is not undetectable: CoreFoundation's
reference-count machinery has an always-on over-release guard that traps (`SIGTRAP` /
`EXC_BREAKPOINT` in `_CFRelease`) when an object is released below a retain count of zero. The race
drives exactly that — the reader retains a pointer the writer already freed, then releases it — so a
well-built repro crashes deterministically, with or without TSan.

Building one that's trustworthy (a green must mean "no bug," not "I missed the window"):

- **Drive the real production accessors** — not a hand-rolled reconstruction. A model proves things
  about the model, not about the SDK.
- **Writer thread: assign fresh, distinct, heap-allocated strings over 15 characters.** Short
  strings become tagged pointers, which are not heap objects and never deallocate — the old value
  never frees, the UAF never happens, and you get a false green. Long unique strings force a real
  allocation and a real free on each overwrite.
- **Reader thread: load via the getter and touch the pointee** (e.g. read `.length`), not just the
  pointer. The dereference is what lands in freed memory during the load→retain window.
- **Overlap for real** — a spin-barrier rendezvous so both threads bust out together and race for
  their full duration, not a single-signal gate that lets one finish before the other wakes.
- **Iterate hard** — hundreds of thousands of iterations. At 500k the `serverSessionId` probe
  crashed 10/10 runs; tune the count up until the crash is effectively deterministic.

The skeleton above is validated against CFString-backed pointees (`NSString`). For a plain-object
pointee, a shallow property/ivar read can false-green — freed memory gets reused by a same-shaped
allocation quickly enough that the read lands on something that still looks "valid." Touch the isa
instead (e.g. `NSStringFromClass([obj class]).length`) to force a class-table lookup that reliably
traps on freed/reused memory, and expect to need a higher iteration count — roughly 10x — to
reproduce as deterministically as the CFString case.

Minimal skeleton (drop into an XCTest case; `raceBlockA:blockB:` is the spin-barrier helper in
`RaceTripwireTests.m`):

```objc
// `property` is a nonatomic strong pointer whose pointee can be freed (e.g. TeakSession.serverSessionId).
// If it's internal, re-declare it in a class extension in the test file so the accessors compile.
- (void)testPropertyDynamicUAF {
  MyType* object = /* a live instance whose accessor you can drive — see the construction note below */;
  const int N = 500000;
  [self raceBlockA:^{
    for (int i = 0; i < N; i++) {
      // Real setter: objc_storeStrong releases the prior value. Fresh >15-char heap string each time.
      object.property = [[NSString alloc] initWithFormat:@"race-probe-value-%d", i];
    }
  }
            blockB:^{
              for (int i = 0; i < N; i++) {
                NSString* s = object.property;  // real getter: nonatomic load; ARC retains into s
                (void)s.length;                 // touch the pointee inside the load->retain window
              }
            }];
}
```

**Construction note:** you only need an instance whose accessors you can drive, not a fully wired
one. If the type's designated initializer has side effects, or its `dealloc` assumes init ran (e.g.
it removes an observer that only init registered), construct a bare instance and keep it alive for
the test's duration rather than letting it deinit — the synthesized accessors are the real
production code regardless of whether init ran.

Then apply the **revert check**: run it against the unfixed property and watch it crash; apply the
fix (§4) and watch the crash vanish. Red→green.

## 4. Why `atomic` fixes the nonatomic-strong UAF

Declaring the property `atomic` (strong) routes reads through `objc_getProperty`, which **retains
the value under the property's per-slot spinlock and hands the reader a +1 snapshot.** The reader
now holds its own strong reference across the dereference, so the writer's concurrent release can't
free the object out from under it — the load→retain gap is closed.

This is a different mechanism from aligned-load atomicity. On arm64 the pointer read already doesn't
*tear*; that was never the problem. The problem is *free-during-use*, and only a retained snapshot
(or a lock held across both the read and the use) prevents it. So the fix has two requirements:

- every read goes **through the accessor** — a direct ivar read bypasses the spinlock and reopens
  the gap, and
- multi-read sites **capture to a local** once, then use the local — re-reading the property for
  each use reopens the window between reads.

## 5. Harness limitation and the standing workflow

The dynamic crash repro takes down the whole test process — the CF trap is a hard crash, not an
assertion failure. In a shared test lane that aborts every sibling test in the same run. Until an
isolated per-test death-test harness exists, that shapes how these tests ship:

**Each fix ships its own red→green test in the same PR as the fix.** We do not carry standing red
tests on a branch. The sequence for any concurrency fix is: add the failing test → watch it go red
(crash or assert) → apply the fix → watch the suite go green → ship both together. A green branch
stays green; a red appears only transiently, inside the fix PR that resolves it.

Some race classes don't fit a reliable in-process dynamic repro at all — forced lock-inversion
deadlocks (which hang rather than crash) and dropped-request ordering bugs (which have no data race
to detect and no crash) among them. Those need a different approach — a watchdog timeout, a
forced-interleaving barrier, or a static/structural assertion — chosen when the fix is tackled,
rather than a copy of the crash-repro pattern above.

Cross-object KVO observer add/remove is another: an unserialized add on one session racing a remove
on another for the shared `deviceConfiguration` corrupts KVO's per-object observation info, which
crashes somewhere later and nondeterministically, not at the racing site. The fix serializes all
add/remove under one lock and bounds the observer set by detaching at replacement; the guard is
structural — assert the removal is idempotent and that replacement deterministically detaches the
outgoing session (see `RaceTripwireTests`), rather than trying to trap the corruption. The revert
check still applies: drop the flag or the detach call and watch the structural assertions go red.

## 6. Quick reference

| Shared state | Detector | Signal | Example source |
|---|---|---|---|
| Mutable container (dict/array) | ThreadSanitizer | `race on NSMutableDictionary` | `userProfile` string-attributes dict |
| nonatomic-strong, freeable pointee | Dynamic crash repro (CF over-release trap) | `SIGTRAP` in `_CFRelease` | `TeakSession.serverSessionId` |
| Immortal scalar/pointer | Static atomic-declaration assertion | assertion red | state-machine fields |
| Cross-object KVO add/remove (shared observee) | Structural assertion (idempotent removal + detached-at-replacement) | assertion red | `TeakSession` deviceConfiguration observers |
| Deadlock / dropped-order | No in-process race signal | case-by-case: watchdog, barrier, structural | — |

Whatever the technique, it isn't a guard until you've run the **revert check** and watched it fail.
