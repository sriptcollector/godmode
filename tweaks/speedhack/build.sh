#!/bin/sh
# Builds SpeedHack.dylib (arm64, iOS 15+) next to this script.
set -e
cd "$(dirname "$0")"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDK" -miphoneos-version-min=15.0 \
  -dynamiclib -fobjc-arc -framework UIKit -framework Foundation \
  -install_name @rpath/SpeedHack.dylib -o SpeedHack.dylib SpeedHack.m
echo "$(pwd)/SpeedHack.dylib"
