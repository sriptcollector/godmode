#!/usr/bin/env bash
# curl -fsSL godmode.orion-jones.com/app | bash
# Downloads the GPS Spoofer Installer app into ~/Applications and opens it. Fetched by curl, the app carries
# no quarantine flag, so it opens without Gatekeeper's "can't verify" block.
set -euo pipefail

main() {
  [ "$(uname -s)" = Darwin ] || { echo "GPS Spoofer installs from a Mac." >&2; exit 1; }
  local app="GPS Spoofer Installer.app" dest="$HOME/Applications" tmp
  tmp="$(mktemp -d)"
  echo "Downloading the GPS Spoofer installer…"
  curl -fL --progress-bar -o "$tmp/i.zip" https://godmode.orion-jones.com/GPS-Spoofer-Installer.zip
  mkdir -p "$dest"
  rm -rf "${dest:?}/$app"
  ditto -x -k "$tmp/i.zip" "$dest"
  rm -rf "$tmp"
  open "$dest/$app"
  echo "✓ The GPS Spoofer installer just opened. Follow it from there; you can close Terminal."
}

main "$@"
