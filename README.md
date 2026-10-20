# GODMODE

Mod the apps on my iPhone from my Mac while it's plugged in. No jailbreak.

```
gm status                          # phone, iOS, dev mode, which GODMODE apps are on it
gm patch instagram                 # Instagram with Reels tab hidden + GodModeKit, installed over USB
gm patch all                       # every social app in mods/
gm speed instagram 2               # make Instagram's UI run 2x (0.25 … 5)
gm companion                       # build + install the GODMODE phone app
gm gps la                          # fake the phone's GPS (la/nyc/tokyo/… or lat,lon; `gm gps off`)
gm ideas                           # what else to build
```

## The GODMODE phone app (`gm companion`)

Runs on the phone, no computer needed once installed:

- **Device** — live thermal / battery / RAM / disk, plus a **Live Activity**: one tap pins thermal,
  battery and RAM to your Lock Screen and Dynamic Island, refreshed every few seconds.
- **Speed** — scrub the app's own UI from 0.1x to 6x, and a button to toggle Reduce Motion system-wide.
- **AI** — a private scratchpad on Apple's on-device model (FoundationModels, iOS 26+). Nothing leaves the phone.
- **Mods** — the catalog, with the one-line `gm patch` command per app.
- **More** — GPS spoof instructions + the ideas backlog.

Built as two targets: the app and a WidgetKit extension (`com.orionjones.godmode.widget`) that draws
the Live Activity. Both share `ios/Shared/GMActivity.swift`; the app pushes fresh telemetry on a timer,
so no App Group is needed.

## How it works

```
decrypted .ipa ──cyan──▶ + tweak dylibs (SCInsta/YTLite, GodModeKit) + new bundle id
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
| `tweaks/godmodekit/` | our own dylib, injected into every patched app (see below) |
| `ios/` | GODMODE companion app (SwiftUI): device telemetry, speed lab, mod catalog, ideas |

The re-signed apps get **their own bundle id** (`com.orionjones.godmode.<app>`) so they sit next to
the App Store version. That's deliberate: re-signing an app under its real App Store bundle id is
what has been getting developer accounts banned. The tradeoff is that the modded app doesn't get push notifications.

## GodModeKit: on the phone, live, no computer

Inside any patched app, **three-finger double-tap** or **two-finger hold (1s)** opens the GODMODE menu:

- **Edit layout:** tap anything (a nav-bar tab, a button, a whole section), use *bigger*/*smaller* to adjust the
  selection, then **HIDE**. It disappears immediately. Rules are saved per app and re-applied 4×/sec, so
  rebuilt screens stay clean. Hidden tabs in a tab row collapse, and the remaining tabs spread out to fill the gap.
  *Hidden items* lists every rule so you can bring any of them back.
- **UI speed:** 0.25x to 5x for every animation in that app, applied instantly.
- **Daily limit:** after N minutes a day the app goes grayscale and runs at slow motion.

GodModeKit also patches a common sideloading crash: re-signed apps lose their App Group entitlement,
so it gives them a private folder instead (Reddit crashed on launch without this).

Recipes can preset an app's own tweak settings (`"defaults"` in `mods/*.json`). Instagram ships with
Reels tab, ads, Meta AI and suggested posts/reels/accounts already off.

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
- iOS 27 has no system-wide animation-speed control. The old no-jailbreak tools (e.g. AnimationSpeed)
  wrote SpringBoard settings through kernel/CoreTrust bugs that Apple patched in iOS 16.x/17.0.1. On a stock
  iOS 27 phone, speed changes happen per app, through GodModeKit.
- Recipe IPAs come from archive.org and are often older than the App Store version. If an app forces an update,
  find a newer decrypted IPA and pass `--ipa`.
- Developer Mode can only be switched on from the phone itself. `gm devmode` reveals the toggle.
- Instagram can flag modded clients. Use at your own risk on accounts you care about.

## Mods

| app | status | tweak |
|---|---|---|
| Instagram | ready | [SCInsta](https://github.com/SoCuul/SCInsta): hide Reels/Explore/Create tabs, reorder tab bar, no ads/Meta AI, no suggested posts, downloads, keep deleted DMs, no seen receipts |
| YouTube | ready | [YTLite](https://github.com/dayanch96/YTLite): no ads, hide Shorts, background play, downloads |
| X, Reddit, Discord | ready | GodModeKit only: tap-to-hide nav bar editor, speed, limit |
| Telegram | dropped | crashes in CloudKit: the re-signed copy has no iCloud entitlement |
| Snapchat, WhatsApp, Messenger | skipped | they detect re-signed clients and ban accounts |
| selftest | ready | SpeedHack only. `gm patch selftest --ipa <any decrypted ipa>` proves the pipeline |
