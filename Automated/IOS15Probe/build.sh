#!/bin/zsh
# usage: build.sh <case A-H> [min-ios=15.0] [identity] [profile.mobileprovision] [bundle-id]
# Bundle id defaults to io.teak.probe.<case> so all cases install side by side (needs a wildcard profile).
# Builds out/Probe-<case>.app for a physical device. One case per binary (a tapped launch has no env).
# Signs only when identity and profile are given. Case G needs libprobe_dl, linked in only for G.
set -e
cd "$(dirname "$0")"
CASE=$1; MIN=${2:-15.0}; ID=$3; PROF=$4; BID=${5:-io.teak.probe.$CASE}
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
APP=out/Probe-$CASE.app
CF=(-target arm64-apple-ios$MIN -isysroot $SDK -fobjc-arc -g -DPROBE_CASE="\"$CASE\"")
rm -rf $APP; mkdir -p $APP/Frameworks
clang $CF -dynamiclib -install_name @rpath/libprobe.dylib -framework UIKit -framework Foundation probe.m libprobe.m -o $APP/Frameworks/libprobe.dylib
clang $CF -dynamiclib -install_name @rpath/libprobe_dl.dylib -framework UIKit -framework Foundation probe.m libprobe_dl.m -o $APP/Frameworks/libprobe_dl.dylib
clang $CF -DPROBE_DLOPEN_G -framework UIKit -framework Foundation main.m probe.m -L$APP/Frameworks -lprobe -Wl,-rpath,@executable_path/Frameworks -o $APP/Probe
cat > $APP/Info.plist <<P
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Probe</string><key>CFBundleIdentifier</key><string>$BID</string>
<key>CFBundleName</key><string>Probe$CASE</string><key>CFBundleDisplayName</key><string>Probe $CASE</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1</string><key>MinimumOSVersion</key><string>$MIN</string><key>UILaunchScreen</key><dict/>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array></dict></plist>
P
if [ -n "$ID" ] && [ -n "$PROF" ]; then
  cp "$PROF" $APP/embedded.mobileprovision
  security cms -D -i "$PROF" | plutil -extract Entitlements xml1 -o out/ent.plist -
  codesign -f -s "$ID" $APP/Frameworks/*.dylib
  codesign -f -s "$ID" --entitlements out/ent.plist $APP
fi
echo "built $APP"
