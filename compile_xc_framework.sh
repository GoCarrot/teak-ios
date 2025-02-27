#!/bin/bash

set -eu
set -o pipefail
set -x

buildtype=${BUILD_TYPE:-Release}

build() {
  BASE_DIRECTORY="$(pwd)/TeakFramework"
  SIMULATOR_PATH="${BASE_DIRECTORY}/simulator"
  IOS_PATH="${BASE_DIRECTORY}/ios"

  rm -fr "${BASE_DIRECTORY}"
  mkdir -p "${BASE_DIRECTORY}"

  xcodebuild \
    -project Teak.xcodeproj \
    -sdk iphonesimulator \
    -target Framework \
    -destination="generic/platform=iOS Simulator" \
    -configuration $buildtype \
    BUILD_DIR="${SIMULATOR_PATH}" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARIES_FOR_DISTRIBUTION=YES \
    clean \
    build

  xcodebuild \
    -project Teak.xcodeproj \
    -sdk iphoneos \
    -target Framework \
    -destination="generic/platform=iOS" \
    -configuration $buildtype \
    BUILD_DIR="${IOS_PATH}" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARIES_FOR_DISTRIBUTION=YES \
    clean \
    build

  xcodebuild \
    -create-xcframework \
    -framework ${SIMULATOR_PATH}/${buildtype}-iphonesimulator/Teak.framework \
    -framework ${IOS_PATH}/${buildtype}-iphoneos/Teak.framework \
    -output "${BASE_DIRECTORY}/Teak.xcframework"
}

build
