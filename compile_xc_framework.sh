#!/bin/bash

set -eu
set -o pipefail
set -x

buildtype=${BUILD_TYPE:-Release}

build() {
  BASE_DIRECTORY="$(pwd)/TeakFramework"
  SIMULATOR_PATH="${BASE_DIRECTORY}/simulator.xcarchive"
  IOS_PATH="${BASE_DIRECTORY}/ios.xcarchive"

  rm -fr "${BASE_DIRECTORY}"
  mkdir -p "${BASE_DIRECTORY}"

  xcodebuild \
    -project Teak.xcodeproj \
    -sdk iphonesimulator \
    -scheme Framework \
    -destination="generic/platform=iOS Simulator" \
    -configuration $buildtype \
    -archivePath "${SIMULATOR_PATH}" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARIES_FOR_DISTRIBUTION=YES \
    clean \
    archive

  xcodebuild \
    -project Teak.xcodeproj \
    -sdk iphoneos \
    -scheme Framework \
    -destination="generic/platform=iOS" \
    -configuration $buildtype \
    -archivePath "${IOS_PATH}" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARIES_FOR_DISTRIBUTION=YES \
    clean \
    archive

  xcodebuild \
    -create-xcframework \
    -framework ${SIMULATOR_PATH}/Products/Library/Frameworks/Teak.framework \
    -debug-symbols ${SIMULATOR_PATH}/dSYMS/Teak.framework.dSYM \
    -framework ${IOS_PATH}/Products/Library/Frameworks/Teak.framework \
    -debug-symbols ${IOS_PATH}/dSYMS/Teak.framework.dSYM \
    -output "${BASE_DIRECTORY}/Teak.xcframework"
}

build
