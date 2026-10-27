#!/usr/bin/env bash
# Builds "GPS Spoofer Installer.app" (universal) and zips it to site/GPS-Spoofer-Installer.zip.
# Signs with a "Developer ID Application" identity and notarizes with the notarytool keychain profile
# "godmode-notary" when they exist; otherwise ad-hoc signs (fine for testing, blocked by Gatekeeper
# when downloaded).
set -euo pipefail
cd "$(dirname "$0")"
NAME="GPS Spoofer Installer"
B=.build; APP="$B/$NAME.app"; ZIP=../site/GPS-Spoofer-Installer.zip
rm -rf "$B"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc -O -parse-as-library -target "$arch-apple-macos13.0" -o "$B/bin-$arch" Installer.swift
done
lipo -create -output "$APP/Contents/MacOS/$NAME" "$B/bin-arm64" "$B/bin-x86_64"

swift icon.swift "$B/AppIcon.iconset" && iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$B/AppIcon.iconset"
cp ../install.sh "$APP/Contents/Resources/install.sh"  # offline fallback; the app prefers the live copy

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>com.orionjones.godmode.installer</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>$(git rev-list --count HEAD)</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Shows the password prompt Apple's developer tools need.</string>
</dict></plist>
EOF

ID="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
if [ -n "$ID" ]; then
  codesign --force --options runtime --timestamp --sign "$ID" "$APP"
  if xcrun notarytool history --keychain-profile godmode-notary >/dev/null 2>&1; then
    ditto -c -k --keepParent "$APP" "$B/notarize.zip"
    xcrun notarytool submit "$B/notarize.zip" --keychain-profile godmode-notary --wait
    xcrun stapler staple "$APP"
    echo "signed + notarized with $ID"
  else
    echo "signed with $ID but NOT notarized (no 'godmode-notary' notarytool profile)"
  fi
else
  codesign --force --sign - "$APP"
  echo "ad-hoc signed only: downloads will be blocked by Gatekeeper"
fi
rm -f "$ZIP"; ditto -c -k --keepParent "$APP" "$ZIP"
ls -lh "$ZIP"
