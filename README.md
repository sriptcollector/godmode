# GODMODE

Mod the apps on my iPhone from my Mac while it's plugged in. No jailbreak.

```
gm status                          # phone, iOS, dev mode, which GODMODE apps are on it
gm patch instagram --ipa IG.ipa    # Instagram with Reels tab hidden + SpeedHack, installed over USB
gm speed instagram 2               # make Instagram's UI run 2x (0.25 … 5)
gm companion                       # build + install the GODMODE phone app
gm ideas                           # what else to build
```

## How it works

```
decrypted .ipa ──cyan──▶ + tweak dylibs (SCInsta, SpeedHack) + new bundle id
               ──xcodebuild (ASC API key)──▶ mint dev profile that includes this phone
               ──codesign──▶ re-signed .app ──devicectl──▶ installed on phone
```

| piece | what it is |
|---|---|
| `gm` | Python CLI (stdlib only) |
| `gmlib/device.py` | `xcrun devicectl` wrappers: list, install, launch, push files into an app's container |
| `gmlib/sign.py` | mints a profile for any bundle id via a throwaway Xcode project, then re-signs inside-out |
| `gmlib/patch.py` | the IPA pipeline above |
| `mods/*.json` | one recipe per app: which tweaks, which bundle id |
| `tweaks/speedhack/` | our own dylib: sets `window.layer.speed` in any patched app. 3-finger double-tap = speed picker |
| `ios/` | GODMODE companion app (SwiftUI): device telemetry, speed lab, mod catalog, ideas |

The re-signed apps get **their own bundle id** (`com.orionjones.godmode.<app>`) so they sit next to
the App Store version. That's deliberate: re-signing an app under its real App Store bundle id is
what has been getting developer accounts banned. The tradeoff is that the modded app doesn't get push notifications.

## Setup (one time)

```
brew install xcodegen libimobiledevice
pipx install https://github.com/asdfzxcvbn/pyzule-rw/archive/main.zip   # provides `cyan`
```

`~/.godmode/config.json` (not committed) holds the team id and the App Store Connect API key used to sign:

```json
{ "team": "482FP5Y9AN", "asc_key_path": "~/.appstoreconnect/private_keys/AuthKey_XXXX.p8",
  "asc_key_id": "XXXX", "asc_issuer_id": "…" }
```

## Getting a decrypted IPA

App Store apps are FairPlay-encrypted, and injected code can't run in an encrypted binary. `gm patch` checks
this (`cryptid`) and refuses encrypted input. You need a *decrypted* IPA of the app version the tweak
supports (SCInsta v1.1.1 is tested on Instagram 418.2.0). SCInsta's wiki points to archive.org for these.

## Limits

- Free/dev-signed apps expire with the profile (about a year on a paid team). Re-run `gm patch` to refresh.
- iOS has no system-wide animation-speed setting like Android does. SpeedHack speeds up *patched* apps;
  the companion app's Speed tab can trigger a Shortcut that toggles Reduce Motion.
- Developer Mode can only be switched on from the phone itself. `gm devmode` reveals the toggle.
- Instagram can flag modded clients. Use at your own risk on accounts you care about.

## Mods

| app | status | tweak |
|---|---|---|
| Instagram | ready | [SCInsta](https://github.com/SoCuul/SCInsta): hide Reels/Explore/Create tabs, reorder tab bar, no ads/Meta AI, no suggested posts, downloads, keep deleted DMs, no seen receipts |
| YouTube | next | YTLite / uYouEnhanced: no Shorts tab, no ads, background play |
| TikTok | next | BHTikTok |
| selftest | ready | SpeedHack only. `gm patch selftest --ipa <any decrypted ipa>` proves the pipeline |
