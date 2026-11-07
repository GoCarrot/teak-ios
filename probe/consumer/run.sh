#!/bin/bash
# Build the consumer app (sim + generic device), launch on a simulator running the
# newest installed iOS runtime, deliver a mutable-content push, collect logs.
#   run.sh <frameworks_dir> <scene|legacy|swiftui> <out_dir>
set -uo pipefail
FW="$1"; MODE="$2"; OUT="$(mkdir -p "$3" && cd "$3" && pwd)"
HERE="$(cd "$(dirname "$0")" && pwd)"
PROJ="$OUT/proj-$MODE"
LOG="$OUT/$MODE"; mkdir -p "$LOG"
fail=0

bundle exec ruby "$HERE/generate.rb" "$FW" "$PROJ" "$MODE" || exit 1

{ xcodebuild -version; xcrun --sdk iphoneos --show-sdk-version; xcrun --sdk iphonesimulator --show-sdk-version; } | tee "$LOG/toolchain.txt"

xcodebuild -project "$PROJ/Consumer.xcodeproj" -scheme Consumer -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$PROJ/dd-device" build > "$LOG/build-device.log" 2>&1 \
  && echo "device build: OK" || { echo "device build: FAILED"; fail=1; }
grep -E 'warning:|error:' "$LOG/build-device.log" | sort -u > "$LOG/device-diagnostics.txt"

xcodebuild -project "$PROJ/Consumer.xcodeproj" -scheme Consumer -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$PROJ/dd-sim" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build > "$LOG/build-sim.log" 2>&1 \
  && echo "sim build: OK" || { echo "sim build: FAILED"; tail -40 "$LOG/build-sim.log"; exit 1; }
grep -E 'warning:|error:' "$LOG/build-sim.log" | sort -u > "$LOG/sim-diagnostics.txt"

APP="$PROJ/dd-sim/Build/Products/Debug-iphonesimulator/Consumer.app"
echo "== app binary build version" | tee "$LOG/vtool.txt"
vtool -show-build "$APP/Consumer" | tee -a "$LOG/vtool.txt"

# Skip device-specific runtime variants (identifier suffix like -iPhone19-4); they reject generic device types.
RUNTIME=$(xcrun simctl list runtimes -j | PROBE_RUNTIME_MAJOR="${PROBE_RUNTIME_MAJOR:-}" ruby -rjson -e 'm=ENV["PROBE_RUNTIME_MAJOR"].to_s; r=JSON.parse(STDIN.read)["runtimes"].select{|x| x["platform"]=="iOS" && x["isAvailable"] && x["identifier"]=~/SimRuntime\.iOS-[\d-]+$/ && (m.empty? || x["version"].start_with?(m+"."))}.max_by{|x| Gem::Version.new(x["version"])}; puts r["identifier"]')
DEVTYPE=$(xcrun simctl list devicetypes -j | ruby -rjson -e 'd=JSON.parse(STDIN.read)["devicetypes"].select{|x| x["name"]=~/^iPhone \d+$/}.max_by{|x| x["name"][/\d+/].to_i}; puts d["identifier"]')
echo "runtime: $RUNTIME devicetype: $DEVTYPE" | tee -a "$LOG/toolchain.txt"
UDID=$(xcrun simctl create "probe-$MODE" "$DEVTYPE" "$RUNTIME")
xcrun simctl boot "$UDID"; xcrun simctl bootstatus "$UDID" -b > /dev/null
xcrun simctl install "$UDID" "$APP" || { echo "install FAILED"; exit 1; }

xcrun simctl spawn "$UDID" log stream --level debug --style compact \
  --predicate 'process == "Consumer" OR process == "ConsumerNSE"' > "$LOG/device-log.txt" 2>&1 &
LOGPID=$!
sleep 3
xcrun simctl privacy "$UDID" grant notifications io.teak.probe.consumer 2>/dev/null || true
xcrun simctl launch --console-pty "$UDID" io.teak.probe.consumer > "$LOG/console.txt" 2>&1 &
sleep 25

cat > "$OUT/push.json" <<'J'
{"Simulator Target Bundle":"io.teak.probe.consumer","aps":{"alert":{"title":"probe","body":"c-2181"},"mutable-content":1}}
J
# Background the app first so the push goes through the NSE + banner path.
xcrun simctl launch "$UDID" com.apple.Preferences > /dev/null 2>&1
sleep 3
xcrun simctl push "$UDID" io.teak.probe.consumer "$OUT/push.json" && echo "push sent"
sleep 10
xcrun simctl launch "$UDID" io.teak.probe.consumer > /dev/null 2>&1
sleep 8
sleep 30
kill $LOGPID 2>/dev/null

echo "== probe markers"
grep -h 'PROBE' "$LOG/console.txt" "$LOG/device-log.txt" | sed 's/^.*PROBE/PROBE/' | sort | uniq -c
echo "== teak log lines: $(grep -c 'Teak:' "$LOG/console.txt" "$LOG/device-log.txt" | tr '\n' ' ')"
grep -ho '"event_type":"[a-z._]*"' "$LOG/console.txt" | sort | uniq -c | tee "$LOG/teak-events.txt"
NEW_CRASHES=$(find ~/Library/Logs/DiagnosticReports -iname '*onsumer*' -newer "$OUT/push.json" 2>/dev/null; find ~/Library/Logs/DiagnosticReports -iname '*onsumer*' -newer "$LOG/toolchain.txt" 2>/dev/null)
NEW_CRASHES=$(echo "$NEW_CRASHES" | sort -u | grep . )
[ -n "$NEW_CRASHES" ] && { echo "CRASH REPORTS FOUND (this run)"; echo "$NEW_CRASHES" | while read c; do cp "$c" "$LOG/"; done; fail=1; }
grep -q 'PROBE-NSE: contentHandler fired' "$LOG/device-log.txt" "$LOG/console.txt" && echo "NSE: OK" || echo "NSE: no contentHandler marker (informational: simctl push never invoked the NSE on iOS 18.6 either)"
grep -q 'PROBE: didFinishLaunching' "$LOG/console.txt" "$LOG/device-log.txt" && echo "launch: OK" || { echo "launch: no marker"; fail=1; }
grep -q 'notification.registration.success' "$LOG/console.txt" && echo "push registration: OK" || { echo "push registration: no success event"; fail=1; }
for m in applicationDidBecomeActive applicationWillResignActive; do
  grep -q "\"callback\":\"$m:\"" "$LOG/console.txt" && echo "teak lifecycle $m: seen" || { echo "teak lifecycle $m: MISSING"; fail=1; }
done
grep -ho 'PROBE: openSettings -> [01]' "$LOG/console.txt" | head -1 | sed 's/^/teak /'
grep -q 'BUG IN CLIENT OF UIKIT' "$LOG/device-log.txt" && grep -h 'BUG IN CLIENT OF UIKIT' "$LOG/device-log.txt" | head -2 | cut -c1-300
if [ "$MODE" = scene ]; then grep -q 'PROBE: sceneDidBecomeActive' "$LOG/console.txt" "$LOG/device-log.txt" && echo "scene: OK" || { echo "scene: no marker"; fail=1; }; fi
xcrun simctl shutdown "$UDID"; xcrun simctl delete "$UDID"
exit $fail
