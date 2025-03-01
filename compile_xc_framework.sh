#!/usr/bin/env bash

set -Eeuo pipefail
trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)

usage() {
  cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-f] -p param_value arg1 [arg2...]

Script description here.

Available options:

-h, --help      Print this help and exit
-v, --verbose   Print script debug info
-d, --debug     Compile Frameworks with symbols and without optimizations
EOF
  exit
}

cleanup() {
  trap - SIGINT SIGTERM ERR EXIT
  # script cleanup here
}

setup_colors() {
  if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
    NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
  else
    NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
  fi
}

msg() {
  echo >&2 -e "${1-}"
}

die() {
  local msg=$1
  local code=${2-1} # default exit status 1
  msg "$msg"
  exit "$code"
}

parse_params() {
  # default values of variables set from params
  debug_build=0
  verbose=0
  param=''

  while :; do
    case "${1-}" in
    -h | --help) usage ;;
    -v | --verbose) set -x; verbose=1 ;;
    --no-color) NO_COLOR=1 ;;
    -d | --debug) debug_build=1 ;;
    -?*) die "Unknown option: $1" ;;
    *) break ;;
    esac
    shift
  done

  args=("$@")

  return 0
}

parse_params "$@"
setup_colors

if [ $debug_build -eq 1 ]; then
  buildtype="Debug"
else
  buildtype="Release"
fi

if [ $verbose -eq 0 ]; then
  quiet="-quiet"
else
  quiet=""
fi

BASE_DIRECTORY="${script_dir}/TeakFramework"

build() {
  SIMULATOR_PATH="${BASE_DIRECTORY}/simulator.xcarchive"
  IOS_PATH="${BASE_DIRECTORY}/ios.xcarchive"

  msg "Building Teak.xcframework for ${buildtype}"
  msg "Cleaning previous build at ${BASE_DIRECTORY}"
  rm -fr "${BASE_DIRECTORY}"
  mkdir -p "${BASE_DIRECTORY}"

  msg "Building for iOS Simulator"
  xcodebuild \
    ${quiet} \
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

  msg "Building for iOS Device"
  xcodebuild \
    ${quiet} \
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

  msg "Generating XCFramework"
  if [ $buildtype = "Release" ]; then
    xcodebuild \
      -create-xcframework \
      ${quiet} \
      -framework ${SIMULATOR_PATH}/Products/Library/Frameworks/Teak.framework \
      -debug-symbols ${SIMULATOR_PATH}/dSYMs/Teak.framework.dSYM \
      -framework ${IOS_PATH}/Products/Library/Frameworks/Teak.framework \
      -debug-symbols ${IOS_PATH}/dSYMs/Teak.framework.dSYM \
      -output "${BASE_DIRECTORY}/Teak.xcframework"
  else
    xcodebuild \
      ${quiet} \
      -create-xcframework \
      -framework ${SIMULATOR_PATH}/Products/Library/Frameworks/Teak.framework \
      -framework ${IOS_PATH}/Products/Library/Frameworks/Teak.framework \
      -output "${BASE_DIRECTORY}/Teak.xcframework"
  fi
}

move_to_repo() {
  msg "Moving built XCFramework to ${script_dir}/teak-ios-framework"
  # cp -r "${BASE_DIRECTORY}/Teak.xcframework" "../teak-ios-framework"
}

build
move_to_repo
