#!/usr/bin/env bash
# GODMODE one-shot installer: Mac toolchain → GODMODE app on the plugged-in iPhone → standalone GPS pairing.
# Safe to re-run; every step skips itself when it's already done.
#
#   curl -fsSL godmode.orion-jones.com | bash
#   ./install.sh                     from a checkout
set -euo pipefail

REPO=sriptcollector/godmode
IDEVICE_VER=v0.1.68
IDEVICE_XCF_SHA=c9eccdd1942de756d746a2569d93302774ab0eff1cff314ec8118f768b3d8dc7
IDEVICE_TOOLS_ARM_SHA=fc4c2a74a3d2899bc33a7c2ed42d367e843b9dd6854bb3b1b257274b1ce712fa
IDEVICE_TOOLS_INTEL_SHA=ba27ffd646a06ac411e185607343a8e8da437d1fa52a24a2d7c6411d4d8d1447
STATE="$HOME/.godmode"

say()  { printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
die()  { printf '\n\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
wait_enter() { read -r -p "  $* — press Enter when done " _ </dev/tty; }
ask()  { local a; read -r -p "  $1 " a </dev/tty; printf '%s' "$a"; }

# Everything runs inside main so a half-downloaded `curl | bash` never executes a partial script.
main() {
[ "$(uname -s)" = Darwin ] || die "GODMODE needs a Mac."
if [ "$(uname -m)" = arm64 ]; then
  BREW_BIN=/opt/homebrew/bin/brew; TOOLS_ARCH=arm; TOOLS_SHA=$IDEVICE_TOOLS_ARM_SHA
else
  BREW_BIN=/usr/local/bin/brew; TOOLS_ARCH=intel; TOOLS_SHA=$IDEVICE_TOOLS_INTEL_SHA
fi

# ── 1. Homebrew + CLI deps ──────────────────────────────────────────────────────────────────────
say "Homebrew + tools"
if ! command -v brew >/dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
eval "$("$BREW_BIN" shellenv)"
for f in xcodegen libimobiledevice pipx; do
  brew list --formula "$f" >/dev/null 2>&1 || brew install "$f"
done
pipx ensurepath >/dev/null 2>&1 || true
export PATH="$HOME/.local/bin:$PATH"
command -v pymobiledevice3 >/dev/null || pipx install pymobiledevice3 || echo "  (pymobiledevice3 failed — only \`gm gps\` over the cable needs it)"
ok "xcodegen, libimobiledevice, pymobiledevice3"

# ── 2. The repo ─────────────────────────────────────────────────────────────────────────────────
say "GODMODE source"
SELF="${BASH_SOURCE[0]:-}"  # empty when piped from curl
HERE="$( [ -f "$SELF" ] && cd "$(dirname "$SELF")" && pwd || true)"
if [ -n "$HERE" ] && [ -x "$HERE/gm" ] && [ -d "$HERE/gmlib" ]; then
  ROOT="$HERE"
else
  ROOT="$HOME/godmode"
  if [ -d "$ROOT/.git" ]; then
    git -C "$ROOT" pull --ff-only
  else
    # Public repo: plain https clone. Private (owner only): fall back to an authenticated gh clone.
    GIT_TERMINAL_PROMPT=0 git clone -q "https://github.com/$REPO.git" "$ROOT" 2>/dev/null || {
      brew list --formula gh >/dev/null 2>&1 || brew install gh
      gh auth status >/dev/null 2>&1 || gh auth login --web --git-protocol https
      gh repo clone "$REPO" "$ROOT"
    }
  fi
fi
ln -sf "$ROOT/gm" "$(brew --prefix)/bin/gm"
ok "$ROOT  (gm is on your PATH)"

# ── 3. Xcode ────────────────────────────────────────────────────────────────────────────────────
say "Xcode"
find_xcode() { ls -d /Applications/Xcode*.app 2>/dev/null | sort | tail -1; }
XCODE="$(find_xcode)"
if [ -z "$XCODE" ]; then
  brew list --formula mas >/dev/null 2>&1 || brew install mas
  mas install 497799835 || { open "macappstore://apps.apple.com/app/id497799835"; wait_enter "Install Xcode from the App Store"; }
  XCODE="$(find_xcode)"
  [ -n "$XCODE" ] || die "Xcode still not in /Applications."
fi
case "$(xcode-select -p)" in
  "$XCODE"/*) ;;
  *) echo "  pointing xcode-select at $XCODE (sudo)"; sudo xcode-select -s "$XCODE/Contents/Developer" ;;
esac
xcodebuild -license check >/dev/null 2>&1 || sudo xcodebuild -license accept
xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1 || sudo xcodebuild -runFirstLaunch
ok "$XCODE"

# ── 4. Signing ──────────────────────────────────────────────────────────────────────────────────
say "Signing"
mkdir -p "$STATE"
# Team ids Xcode knows about: signed-in accounts first, then any Apple Development certs in the keychain.
detect_teams() {
  python3 - <<'PY'
import os, plistlib, re, subprocess
seen = []
def add(t, name="", free=False):
    if t not in [x[0] for x in seen]:
        seen.append((t, name, free))
def walk(x):
    if isinstance(x, dict):
        if isinstance(x.get("teamID"), str):
            add(x["teamID"], x.get("teamName", ""), x.get("isFreeProvisioningTeam", False))
        for v in x.values(): walk(v)
    elif isinstance(x, list):
        for v in x: walk(v)
try:
    walk(plistlib.load(open(os.path.expanduser("~/Library/Preferences/com.apple.dt.Xcode.plist"), "rb")))
except Exception:
    pass
pems = subprocess.run(["security", "find-certificate", "-a", "-c", "Apple Development", "-p"],
                      capture_output=True, text=True).stdout
for pem in re.findall(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", pems, re.S):
    subj = subprocess.run(["openssl", "x509", "-noout", "-subject"], input=pem,
                          capture_output=True, text=True).stdout
    m = re.search(r"OU\s*=\s*([A-Z0-9]{10})", subj)
    if m:
        add(m.group(1))
for t, name, free in seen:
    print(f"{t}\t{name}{' (free: apps last 7 days)' if free else ''}")
PY
}
if [ -f "$STATE/config.json" ]; then
  ok "using $STATE/config.json"
else
  echo "  GODMODE is signed with your own Apple ID. A free Apple ID works (the app then needs"
  echo "  re-installing every 7 days); a paid developer account lasts a year."
  KEY="$(ask 'App Store Connect API key (.p8) path, or just Enter to sign in to Xcode instead:')"
  if [ -z "$KEY" ] && [ -z "$(detect_teams)" ]; then
    open -a "$XCODE"
    until [ -n "$(detect_teams)" ]; do
      wait_enter "In Xcode › Settings › Accounts, click + and sign in with your Apple ID"
    done
  fi
  TEAMS="$(detect_teams)"
  [ -z "$TEAMS" ] || { echo "  Teams found:"; printf '%s\n' "$TEAMS" | sed 's/^/    /'; }
  DEFAULT_TEAM="$(printf '%s\n' "$TEAMS" | head -1 | cut -f1)"
  TEAM="$(ask "Team ID${DEFAULT_TEAM:+ [$DEFAULT_TEAM]}:")"; TEAM="${TEAM:-$DEFAULT_TEAM}"
  [[ "$TEAM" =~ ^[A-Z0-9]{10}$ ]] || die "a team ID is 10 letters/digits (developer.apple.com › Account › Membership)"
  if [ -n "$KEY" ]; then
    KEY="${KEY/#\~/$HOME}"
    [ -f "$KEY" ] || die "no such file: $KEY"
    KEY_ID="$(basename "$KEY" .p8)"; KEY_ID="${KEY_ID#AuthKey_}"
    ISSUER="$(ask 'Issuer ID (App Store Connect › Users and Access › Integrations):')"
    TEAM="$TEAM" KEY="$KEY" KEY_ID="$KEY_ID" ISSUER="$ISSUER" python3 -c '
import json, os
json.dump({"team": os.environ["TEAM"], "asc_key_path": os.environ["KEY"],
           "asc_key_id": os.environ["KEY_ID"], "asc_issuer_id": os.environ["ISSUER"]},
          open(os.path.expanduser("~/.godmode/config.json"), "w"), indent=2)'
  else
    TEAM="$TEAM" python3 -c '
import json, os
json.dump({"team": os.environ["TEAM"]}, open(os.path.expanduser("~/.godmode/config.json"), "w"), indent=2)'
  fi
  ok "saved $STATE/config.json (team $TEAM)"
fi

# ── 5. idevice (prebuilt): the on-phone GPS library + the Mac pairing tool ───────────────────────
say "idevice $IDEVICE_VER"
fetch() {  # fetch <asset> <sha256> <dest-dir>
  local zip="$STATE/dl/$1"
  mkdir -p "$STATE/dl"
  [ -f "$zip" ] || curl -fL --progress-bar -o "$zip" "https://github.com/jkcoxson/idevice/releases/download/$IDEVICE_VER/$1"
  echo "$2  $zip" | shasum -a 256 -c --status || { rm -f "$zip"; die "checksum mismatch on $1"; }
  rm -rf "$3"; mkdir -p "$3"; ditto -x -k "$zip" "$3"
}
XCF="$ROOT/ios/Vendor/IDevice.xcframework"
if [ ! -f "$XCF/.version" ] || [ "$(cat "$XCF/.version")" != "$IDEVICE_VER" ]; then
  T="$(mktemp -d)"
  fetch "idevice-xcframework-$IDEVICE_VER.zip" "$IDEVICE_XCF_SHA" "$T/x"
  SRC="$T/x/swift/IDevice.xcframework"
  # The app does `import IDeviceFFI`; upstream names the module `IDevice`. Keep just the iOS slices.
  for s in ios-arm64 ios-arm64_x86_64-simulator; do
    sed -i '' 's/^module IDevice /module IDeviceFFI /' "$SRC/$s/Headers/module.modulemap"
  done
  rm -rf "$XCF"; mkdir -p "$(dirname "$XCF")"
  xcodebuild -create-xcframework \
    -library "$SRC/ios-arm64/libidevice_ffi.a" -headers "$SRC/ios-arm64/Headers" \
    -library "$SRC/ios-arm64_x86_64-simulator/idevice-ios-sim.a" -headers "$SRC/ios-arm64_x86_64-simulator/Headers" \
    -output "$XCF" >/dev/null
  echo "$IDEVICE_VER" > "$XCF/.version"
  rm -rf "$T" "$STATE/dl/idevice-xcframework-$IDEVICE_VER.zip"
fi
ok "IDevice.xcframework → ios/Vendor"
if [ ! -x "$STATE/bin/idevice-tools" ] || [ "$(cat "$STATE/bin/.version" 2>/dev/null)" != "$IDEVICE_VER" ]; then
  fetch "idevice-tools-macos-$TOOLS_ARCH-$IDEVICE_VER.zip" "$TOOLS_SHA" "$STATE/bin"
  chmod +x "$STATE/bin/"*
  echo "$IDEVICE_VER" > "$STATE/bin/.version"
fi
ok "idevice-tools → ~/.godmode/bin"

# ── 6. The phone ────────────────────────────────────────────────────────────────────────────────
say "iPhone"
phone() { python3 - "$ROOT" "$1" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
from gmlib import device
try:
    d = device.pick()
except device.DeviceError:
    print("none"); sys.exit()
if sys.argv[2] == "devmode":
    print(device.details(d["identifier"]).get("deviceProperties", {}).get("developerModeStatus"))
else:
    print(d.get("deviceProperties", {}).get("name", "iPhone"))
PY
}
until [ "$(phone name)" != none ]; do
  wait_enter "Plug in the iPhone with a cable, unlock it, and tap Trust"
done
ok "$(phone name)"
if [ "$(phone devmode)" != enabled ]; then
  gm devmode || true
  until [ "$(phone devmode)" = enabled ]; do
    wait_enter "On the phone: Settings › Privacy & Security › Developer Mode → On, restart, unlock, tap Turn On"
  done
fi
ok "Developer Mode on"

say "Building + installing the GODMODE app (first build takes a few minutes)"
gm companion

say "Pairing the app with the phone (one time, so GPS works with no Mac)"
if [ -f "$STATE/pairing.plist" ]; then gm pairphone --reuse; else gm pairphone; fi

cat <<'EOF'

  ✓ Installed. Last step on the phone:
     1. App Store → install "LocalDevVPN" (free), open it, tap Connect
     2. Open GODMODE → tap the map → Teleport

  Keep LocalDevVPN connected while spoofing. To update later: re-run this installer.
  Signing expires after 7 days on a free Apple ID (a year on a paid one); re-run to renew.
EOF
}

main "$@"
