# StoreKitProbe

Measures which StoreKit purchases reach Teak's `SKPaymentObserver` (the SK1 queue observer).
It's a measurement, not a pass/fail suite: tests pass regardless, read the `PROBE` lines.

Uses the real `Teak.framework`. `+[PurchaseEvent purchaseSucceeded:]` is swizzled to count
calls, so a Teak report is "Teak would send this purchase". Purchases run against a local
`.storekit` config through `SKTestSession` in an app-hosted XCTest (without a host app the
test server returns "unknown").

```bash
# 1. simulator Teak.framework (own DerivedData; compile_xc_framework would write ../teak-ios-framework)
xcodebuild -project Teak.xcodeproj -scheme Framework -sdk iphonesimulator \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  -derivedDataPath /tmp/probe-dd TEAK_GIT_VERSION=probe build
# 2. generate a throwaway project, run on a simulator
bundle exec ruby Automated/StoreKitProbe/generate_project.rb \
  /tmp/probe-dd/Build/Products/Debug-iphonesimulator /tmp/probe-proj
cd /tmp/probe-proj && PROBE_LOG=/tmp/probe.log TEST_RUNNER_PROBE_LOG=/tmp/probe.log \
  xcodebuild test -project Probe.xcodeproj -scheme Probe -destination "platform=iOS Simulator,name=iPhone 16"
cat /tmp/probe.log
```

Expected on iOS 18.6 (Xcode 16.4):

| test | teakPurchaseSucceededCalls |
|---|---|
| SK1 control (`SKPaymentQueue.add`) | 1 |
| SK2 purchase, observer attached first | 0 |
| SK2 purchase left unfinished, observer attached after | 1 |
| SK2 purchase, `Transaction.updates` listener running, finished | 0 (`updatesDelivered=[]`) |
| `Transaction.updates` started after an unfinished SK2 purchase (positive control) | `updatesDelivered=[tx]` |

Receipt read (`testReceiptAfterSK1Purchases`, `testReceiptAfterSK2Purchases`): run each alone on an erased
simulator, the receipt file persists across tests. On the local StoreKit test server, two SK1 purchases
create the receipt (1668 bytes, product id present once, no growth between purchases); two SK2 purchases,
finished or not, leave `appStoreReceiptURL` pointing at no file. The local receipt isn't a model of the
sandbox/production one; this only shows a receipt read can't be assumed to see SK2 purchases.

The SK1 control and the updates positive control show the harness can see a delivery; the
zeros mean something only because of them.

Gotchas: `SKProductsRequest` reports the config product invalid under `SKTestSession`
(the SK1 control buys by identifier); the swizzle replaces the method, so nothing is sent.

## SK2Observer (C-2320)

`Observer/SK2Observer.m` is its own ObjC-only framework (`nm` shows no `_$s` symbols). It rebinds GOT slots
for `Transaction.finish()` (both the entry point and the async function pointer; callers bind both) and for
`VerificationResult<Transaction>.jwsRepresentation` to C thunks that log, then call through.
`SK2ObserverTests` buys before and after install. The pre-install purchase not showing up is the red.

```bash
cd /tmp/probe-proj && PROBE_LOG=/tmp/probe.log TEST_RUNNER_PROBE_LOG=/tmp/probe.log xcodebuild test -project Probe.xcodeproj \
  -scheme Probe -destination "platform=iOS Simulator,name=iPhone 16" -only-testing:ProbeTests/SK2ObserverTests
```

Expected on iOS 18.2 / 18.4 / 18.6 sims: `finish-hook RESULT … bought=[0, 1, 2] hookSaw=[1, 2]` and
`jws-hook RESULT … matchesPost=true matchesPre=false`. The receipt is `missing` at finish time on the sim (the local
test server writes no SK2 receipt), so that column only means something on a device.

`testTransactionAllFinishedConsumable` asks whether `Transaction.all` lists a finished consumable. Generate the
project twice, once plain and once with `CONSUMABLE_HISTORY=1` (that merges `App/ConsumableHistory.plist`, which
sets `SKIncludeConsumableInAppPurchaseHistory`, into the host app). On the 18.6 sim it's only listed with the key;
on the 17.5 sim it isn't listed either way.
