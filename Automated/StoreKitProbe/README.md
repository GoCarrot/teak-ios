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

The SK1 control and the updates positive control show the harness can see a delivery; the
zeros mean something only because of them.

Gotchas: `SKProductsRequest` reports the config product invalid under `SKTestSession`
(the SK1 control buys by identifier); the swizzle replaces the method, so nothing is sent.
