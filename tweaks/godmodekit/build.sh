#!/bin/sh
# Builds GodModeKit.dylib (arm64, iOS 15+) next to this script.
set -e
cd "$(dirname "$0")"
SDK=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang -arch arm64 -isysroot "$SDK" -miphoneos-version-min=15.0 \
  -dynamiclib -fobjc-arc -Wall -Wno-unused-function -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics \
  -install_name @rpath/GodModeKit.dylib -o GodModeKit.dylib GodModeKit.m
echo "$(pwd)/GodModeKit.dylib"
