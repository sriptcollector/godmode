#!/usr/bin/env bash
# GPS Spoofer one-shot installer: Mac toolchain → GPS Spoofer app on the plugged-in iPhone → standalone GPS pairing.
# Safe to re-run; every step skips itself when it's already done.
#
#   curl -fsSL godmode.orion-jones.com | bash
#   ./install.sh                     from a checkout
#   GM_UI=app                        driven by the GPS Spoofer Installer Mac app (see installer/): progress and
#                                    prompts go to stdout as `::kind text` lines, answers come back on stdin
set -euo pipefail

REPO=sriptcollector/godmode
IDEVICE_VER=v0.1.68
IDEVICE_XCF_SHA=c9eccdd1942de756d746a2569d93302774ab0eff1cff314ec8118f768b3d8dc7
IDEVICE_TOOLS_ARM_SHA=fc4c2a74a3d2899bc33a7c2ed42d367e843b9dd6854bb3b1b257274b1ce712fa
IDEVICE_TOOLS_INTEL_SHA=ba27ffd646a06ac411e185607343a8e8da437d1fa52a24a2d7c6411d4d8d1447
STATE="$HOME/.godmode"

APP=; [ "${GM_UI:-}" = app ] && APP=1

if [ -n "$APP" ]; then
  say()  { local id="$1"; shift; printf '::step %s %s\n' "$id" "$*"; }
  ok()   { printf '::ok %s\n' "$*"; }
  die()  { printf '::fail %s\n' "$*"; exit 1; }
  ask()  { local a; printf '::ask %s\t%s\n' "$1" "${2:-}" >&2; read -r a; printf '%s' "${a:-${2:-}}"; }
  # wait_until <message> <command…>: show the message and re-check every few seconds (or right away when
  # the app's Done button sends a line), so people never have to come back and confirm.
  wait_until() {
    local msg="$1"; shift
    "$@" && return 0
    printf '::wait %s\n' "$msg"
    until "$@"; do read -r -t 4 _ || sleep 1; done
    printf '::resume\n'
  }
  # sudo prompts become the standard macOS password dialog.
  mkdir -p "$HOME/.godmode"
  cat > "$HOME/.godmode/askpass" <<'ASK'
#!/bin/sh
exec osascript -e 'text returned of (display dialog "GPS Spoofer needs your Mac password to set up Apple’s developer tools." default answer "" with hidden answer with title "GPS Spoofer Installer" with icon caution)'
ASK
  chmod +x "$HOME/.godmode/askpass"
  export SUDO_ASKPASS="$HOME/.godmode/askpass" NONINTERACTIVE=1
  sudo() { command sudo -A "$@"; }
else
  say()  { shift; printf '\n\033[1;36m▸ %s\033[0m\n' "$*"; }
  ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
  die()  { printf '\n\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
  ask()  { local a; read -r -p "  $1${2:+ [$2]} " a </dev/tty; printf '%s' "${a:-${2:-}}"; }
  wait_until() {
    local msg="$1"; shift
    until "$@"; do read -r -p "  $msg — press Enter when done " _ </dev/tty; done
  }
fi

# Everything runs inside main so a half-downloaded `curl | bash` never executes a partial script.
main() {
[ "$(uname -s)" = Darwin ] || die "GPS Spoofer needs a Mac."
if [ "$(uname -m)" = arm64 ]; then
  BREW_BIN=/opt/homebrew/bin/brew; TOOLS_ARCH=arm; TOOLS_SHA=$IDEVICE_TOOLS_ARM_SHA
else
  BREW_BIN=/usr/local/bin/brew; TOOLS_ARCH=intel; TOOLS_SHA=$IDEVICE_TOOLS_INTEL_SHA
fi

# ── 1. Homebrew + CLI deps ──────────────────────────────────────────────────────────────────────
say tools "Homebrew + tools"
if ! command -v brew >/dev/null; then
  [ -z "$APP" ] || command sudo -A -v || die "GPS Spoofer needs an administrator account on this Mac."
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
say source "GPS Spoofer source"
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
      [ -z "$APP" ] || die "Couldn't download GPS Spoofer from GitHub. Check your internet connection and try again."
      brew list --formula gh >/dev/null 2>&1 || brew install gh
      gh auth status >/dev/null 2>&1 || gh auth login --web --git-protocol https
      gh repo clone "$REPO" "$ROOT"
    }
  fi
fi
ln -sf "$ROOT/gm" "$(brew --prefix)/bin/gm"
ok "$ROOT  (gm is on your PATH)"

# ── 3. Xcode ────────────────────────────────────────────────────────────────────────────────────
say xcode "Xcode"
find_xcode() { ls -d /Applications/Xcode*.app 2>/dev/null | sort | tail -1; }
have_xcode() { [ -n "$(find_xcode)" ] && [ -x "$(find_xcode)/Contents/Developer/usr/bin/xcodebuild" ]; }
if ! have_xcode; then
  if [ -z "$APP" ]; then
    brew list --formula mas >/dev/null 2>&1 || brew install mas
    mas install 497799835 || open "macappstore://apps.apple.com/app/id497799835"
  else
    open "macappstore://apps.apple.com/app/id497799835"
  fi
  wait_until "Get Xcode from the App Store (it just opened). It's free but big, so this is the slow part. Installation continues by itself once Xcode is installed." have_xcode
fi
XCODE="$(find_xcode)"
case "$(xcode-select -p)" in
  "$XCODE"/*) ;;
  *) echo "  pointing xcode-select at $XCODE (sudo)"; sudo xcode-select -s "$XCODE/Contents/Developer" ;;
esac
xcodebuild -license check >/dev/null 2>&1 || sudo xcodebuild -license accept
xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1 || sudo xcodebuild -runFirstLaunch
ok "$XCODE"

# ── 4. Signing ──────────────────────────────────────────────────────────────────────────────────
say signing "Signing"
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
  KEY=
  if [ -z "$APP" ]; then
    echo "  GPS Spoofer is signed with your own Apple ID. A free Apple ID works (the app then needs"
    echo "  re-installing every 7 days); a paid developer account lasts a year."
    KEY="$(ask 'App Store Connect API key (.p8) path, or just Enter to sign in to Xcode instead:')"
  fi
  has_team() { [ -n "$(detect_teams)" ]; }
  if [ -z "$KEY" ] && ! has_team; then
    open -a "$XCODE"
    wait_until "Sign in to Xcode with your Apple ID: in Xcode, open Settings › Accounts, click +, choose Apple ID and sign in. A free Apple ID is fine." has_team
  fi
  TEAMS="$(detect_teams)"
  DEFAULT_TEAM="$(printf '%s\n' "$TEAMS" | head -1 | cut -f1)"
  if [ -n "$APP" ] && [ "$(printf '%s\n' "$TEAMS" | grep -c .)" = 1 ]; then
    TEAM="$DEFAULT_TEAM"
  else
    [ -z "$TEAMS" ] || { echo "  Teams found:"; printf '%s\n' "$TEAMS" | sed 's/^/    /'; }
    TEAM="$(ask "Which team ID should sign GPS Spoofer?" "$DEFAULT_TEAM")"
  fi
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
say idevice "idevice $IDEVICE_VER"
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
say phone "iPhone"
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
has_phone() { [ "$(phone name)" != none ]; }
devmode_on() { [ "$(phone devmode)" = enabled ]; }
wait_until "Plug your iPhone into this Mac with a cable, unlock it, and tap Trust if it asks." has_phone
ok "$(phone name)"
if ! devmode_on; then
  gm devmode || true
  wait_until "Turn on Developer Mode on the iPhone: Settings › Privacy & Security › Developer Mode → On. It restarts; unlock it and tap Turn On." devmode_on
fi
ok "Developer Mode on"

say build "Building + installing the GPS Spoofer app (first build takes a few minutes)"
gm companion

say pair "Pairing the app with the phone (one time, so GPS works with no Mac)"
if [ -f "$STATE/pairing.plist" ]; then gm pairphone --reuse; else gm pairphone; fi

[ -z "$APP" ] || { printf '::done\n'; return; }
cat <<'EOF'

  ✓ Installed. Last step on the phone:
     1. App Store → install "LocalDevVPN" (free), open it, tap Connect
     2. Open GPS Spoofer → tap the map → Teleport

  Keep LocalDevVPN connected while spoofing. To update later: re-run this installer.
  Signing expires after 7 days on a free Apple ID (a year on a paid one); re-run to renew.
EOF
}

main "$@"
