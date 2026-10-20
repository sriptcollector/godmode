"""What else a stock (non-jailbroken) iPhone + a Mac + a dev cert can actually do.

Each idea is tagged with how it works, so nothing here is fantasy:
  PATCH  — inject a dylib into a re-signed app (same pipeline as the Instagram mod)
  USB    — Mac-side over devicectl / libimobiledevice while plugged in
  APP    — feature of the GODMODE companion app itself
"""

IDEAS = [
    # app mods
    ("PATCH", "YouTube: no Shorts tab, no ads, background play, PiP", "YTLite / uYouEnhanced tweaks — drop-in mods/youtube.json"),
    ("PATCH", "TikTok: no ads, download w/o watermark, hide Live/Shop tabs", "BHTikTok tweak"),
    ("PATCH", "Snapchat: hide Spotlight + Discover, keep chats, no screenshot alert", "SCInsta-style dylib; Snapchat detects re-signs, burner account only"),
    ("PATCH", "Reddit/X: kill promoted posts + 'For You', force chronological", "Apollo-style dylib hooking the feed model"),
    ("PATCH", "Any app: doom-scroll governor — after N minutes the app greys out and slows to 0.25x", "extend SpeedHack with a timer"),
    ("PATCH", "Any app: FLEX in-app inspector — browse its view tree, live-edit labels, read its sandbox files", "inject FLEXing dylib, 3-finger tap to open"),
    ("PATCH", "Any app: grayscale + no-badge 'boring mode' to make an app less addictive", "CIFilter on the key window layer"),
    ("PATCH", "Any app: force dark mode / custom accent color / custom font", "override traitCollection + UIAppearance"),
    ("PATCH", "Any app: log every network request it makes to a file you pull over USB", "NSURLProtocol hook"),
    # USB
    ("USB",   "Screen-record or screenshot the phone from the Mac on demand", "xcrun devicectl / idevicescreenshot"),
    ("USB",   "Live syslog firehose filtered by app — see what Instagram logs", "idevicesyslog | grep"),
    ("USB",   "Spoof GPS location for testing (only while plugged in + DDI mounted)", "pymobiledevice3 developer dvt simulate-location"),
    ("USB",   "Pull any dev-signed app's sandbox (databases, caches) to the Mac", "devicectl device copy from --domain-type appDataContainer"),
    ("USB",   "Battery forensics: cycle count, health, real mAh, charging watts", "idevicediagnostics ioregentry AppleSmartBattery"),
    ("USB",   "One-command backup + diff of what changed on the phone since last time", "idevicebackup2"),
    ("USB",   "Auto-run on plug-in: a launchd watcher that runs `gm sync` when the iPhone appears", "launchd + devicectl list devices"),
    # companion app
    ("APP",   "Speed lab: scrub the companion's own UI from 0.1x to 10x to feel animation curves", "window.layer.speed"),
    ("APP",   "Sensor dashboard: live accelerometer/gyro/barometer/LiDAR depth readouts", "CoreMotion + ARKit"),
    ("APP",   "Thermal + memory monitor with a Live Activity on the lock screen", "ProcessInfo.thermalState + ActivityKit"),
    ("APP",   "Shortcut launcher: one tap to toggle Reduce Motion, Low Power, grayscale", "shortcuts://run-shortcut"),
    ("APP",   "Private on-device AI scratchpad via Apple Foundation Models", "FoundationModels framework"),
]


def render(tag=None):
    lines = []
    for t, idea, how in IDEAS:
        if tag and t != tag.upper():
            continue
        lines.append(f"  [{t:5}] {idea}\n          ↳ {how}")
    return "\n".join(lines)
