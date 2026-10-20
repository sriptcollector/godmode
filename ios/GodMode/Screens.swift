import SwiftUI
import UIKit

// MARK: - Device

struct DeviceView: View {
    @EnvironmentObject var live: LiveActivityController
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Screen {
            Header(title: "DEVICE", sub: "live telemetry")
            Panel {
                Row(k: "model", v: Self.model)
                Row(k: "system", v: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                Row(k: "uptime", v: Self.fmt(ProcessInfo.processInfo.systemUptime))
                Row(k: "cores", v: "\(ProcessInfo.processInfo.activeProcessorCount)")
                Row(k: "ram", v: Self.bytes(Double(ProcessInfo.processInfo.physicalMemory)))
            }
            Panel {
                Row(k: "battery", v: battery, hot: true)
                Row(k: "thermal", v: thermal, hot: ProcessInfo.processInfo.thermalState.rawValue >= 2)
                Row(k: "low power", v: ProcessInfo.processInfo.isLowPowerModeEnabled ? "ON" : "off")
                Row(k: "reduce motion", v: UIAccessibility.isReduceMotionEnabled ? "ON" : "off")
                Row(k: "disk free", v: Self.diskFree)
                Row(k: "ram free", v: "\(Telemetry.freeRAMMB()) MB")
                Row(k: "this app", v: "\(Telemetry.footprintMB()) MB")
            }
            Panel {
                HStack {
                    Text("LOCK SCREEN").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                    Spacer()
                    Text(live.running ? "LIVE" : "off")
                        .font(Theme.mono(10, .bold))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(live.running ? Theme.acid : Theme.line)
                        .foregroundStyle(live.running ? .black : Theme.dim)
                }
                Text("Pin thermal, battery and RAM to your Lock Screen and Dynamic Island as a Live Activity.")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                Button(live.running ? "stop live activity" : "start live activity") {
                    live.running ? live.stop() : live.start()
                }
                .font(Theme.mono(14, .bold))
                .padding(.vertical, 8).frame(maxWidth: .infinity)
                .background(live.running ? Theme.line : Theme.acid)
                .foregroundStyle(live.running ? .white : .black)
                if let e = live.lastError {
                    Text(e).font(Theme.mono(10)).foregroundStyle(.red)
                }
            }
            Text("updated \(tick.formatted(date: .omitted, time: .standard))")
                .font(Theme.mono(10)).foregroundStyle(Theme.dim)
        }
        .onAppear { UIDevice.current.isBatteryMonitoringEnabled = true }
        .onReceive(timer) { tick = $0 }
    }

    private var battery: String {
        let d = UIDevice.current
        let pct = d.batteryLevel < 0 ? "?" : "\(Int(d.batteryLevel * 100))%"
        let state: String = switch d.batteryState {
        case .charging: " ⚡︎ charging"
        case .full: " full"
        case .unplugged: ""
        default: ""
        }
        return pct + state
    }

    private var thermal: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "SERIOUS"
        case .critical: "CRITICAL"
        @unknown default: "?"
        }
    }

    static var model: String {
        var sys = utsname()
        uname(&sys)
        return withUnsafeBytes(of: &sys.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    static var diskFree: String {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let v = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return bytes(Double(v?.volumeAvailableCapacityForImportantUsage ?? 0))
    }

    static func bytes(_ b: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)
    }

    static func fmt(_ t: TimeInterval) -> String {
        let s = Int(t)
        return String(format: "%dd %02dh %02dm", s / 86400, (s % 86400) / 3600, (s % 3600) / 60)
    }
}

// MARK: - Speed

struct SpeedView: View {
    @AppStorage("gm.speed") private var speed: Double = 1.0
    @State private var flip = false
    @State private var spin = false

    private let presets: [Double] = [0.25, 0.5, 1, 2, 4]

    var body: some View {
        Screen {
            Header(title: "SPEED", sub: "core animation clock")
            Panel {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(format: "%.2fx", speed)).font(Theme.mono(44, .bold)).foregroundStyle(Theme.acid)
                    Spacer()
                    Text(speed > 1 ? "faster" : speed < 1 ? "slow-mo" : "stock")
                        .font(Theme.mono(12)).foregroundStyle(Theme.dim)
                }
                Slider(value: $speed, in: 0.1...6)
                HStack {
                    ForEach(presets, id: \.self) { p in
                        Button("\(p.formatted())x") { speed = p }
                            .font(Theme.mono(12, .semibold))
                            .padding(.vertical, 6).frame(maxWidth: .infinity)
                            .background(speed == p ? Theme.acid : Theme.line)
                            .foregroundStyle(speed == p ? .black : .white)
                    }
                }
            }
            Panel {
                Text("TEST RIG").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                HStack(spacing: 24) {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.acid)
                        .frame(width: 44, height: 44)
                        .rotationEffect(.degrees(spin ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
                    Circle().fill(.white)
                        .frame(width: flip ? 64 : 24, height: flip ? 64 : 24)
                        .animation(.spring(duration: 0.6, bounce: 0.5), value: flip)
                        .frame(width: 64, height: 64)
                    Button("bounce") { flip.toggle() }.font(Theme.mono(13, .bold))
                }
                Text("Every animation in this app — including tab switches and sheets — runs on this clock.")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
            }
            Panel {
                Text("PATCHED APPS").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                Text("Every patched app carries GodModeKit. Inside it: three-finger double-tap (or two-finger hold) → UI speed, Edit layout, Daily limit. Works with no computer. From the Mac:")
                    .font(Theme.mono(12))
                Text("gm speed instagram 2").font(Theme.mono(13, .bold)).foregroundStyle(Theme.acid)
            }
            Panel {
                Text("SYSTEM-WIDE").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                Text("iOS 27 has no system-wide animation-speed switch. The old no-jailbreak speed apps used kernel bugs Apple patched in iOS 16/17. Fastest-feeling stock setup: Reduce Motion + Prefer Cross-Fade Transitions. Make a Shortcut named \"GM Motion\" with Set Reduce Motion → Toggle, then:")
                    .font(Theme.mono(12))
                Button("run GM Motion shortcut") {
                    if let url = URL(string: "shortcuts://run-shortcut?name=GM%20Motion") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(Theme.mono(13, .bold))
            }
        }
        .onAppear { spin = true }
    }
}

// MARK: - Mods

struct Mod: Identifiable {
    let id: String
    let app: String
    let tweak: String
    let does: [String]
    let ready: Bool
}

let MODS: [Mod] = [
    Mod(id: "instagram", app: "Instagram", tweak: "SCInsta + GodModeKit",
        does: ["hide Reels tab", "hide Explore / Create tabs", "reorder tab bar", "no ads, no Meta AI",
               "no suggested posts", "download posts/reels/stories", "keep deleted DMs", "no seen receipts"],
        ready: true),
    Mod(id: "youtube", app: "YouTube", tweak: "YTLite + GodModeKit", does: ["no Shorts tab", "no ads", "background play", "downloads"], ready: true),
    Mod(id: "x", app: "X", tweak: "GodModeKit", does: ["tap-to-hide any tab / button", "UI speed", "daily limit"], ready: true),
    Mod(id: "reddit", app: "Reddit", tweak: "GodModeKit", does: ["tap-to-hide any tab / button", "UI speed", "daily limit"], ready: true),
    Mod(id: "discord", app: "Discord", tweak: "GodModeKit", does: ["tap-to-hide any tab / button", "UI speed", "daily limit"], ready: true),
]

struct ModsView: View {
    var body: some View {
        Screen {
            Header(title: "MODS", sub: "patch over usb")
            ForEach(MODS) { m in
                Panel {
                    HStack {
                        Text(m.app.uppercased()).font(Theme.mono(18, .bold))
                        Spacer()
                        Text(m.ready ? "READY" : "QUEUED")
                            .font(Theme.mono(10, .bold))
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(m.ready ? Theme.acid : Theme.line)
                            .foregroundStyle(m.ready ? .black : Theme.dim)
                    }
                    Text(m.tweak).font(Theme.mono(11)).foregroundStyle(Theme.dim)
                    ForEach(m.does, id: \.self) { Text("› \($0)").font(Theme.mono(12)) }
                    if m.ready {
                        Text("gm patch \(m.id)")
                            .font(Theme.mono(11, .bold)).foregroundStyle(Theme.acid)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }
}

// MARK: - Ideas

let IDEAS: [(String, String)] = [
    ("PATCH", "FLEX inspector in any app: view tree, live-edit labels, browse its files"),
    ("PATCH", "Boring mode: grayscale + no badges for any addictive app"),
    ("PATCH", "Force dark mode / custom accent / custom font in any app"),
    ("PATCH", "Log every network request an app makes, pull it over USB"),
    ("USB", "Screenshot / screen-record the phone from the Mac"),
    ("USB", "Live syslog filtered to one app"),
    ("USB", "GPS spoofing while plugged in"),
    ("USB", "Battery forensics: cycles, health, real mAh"),
    ("USB", "Auto-run gm the moment the phone is plugged in"),
    ("APP", "Live sensor wall: accel, gyro, barometer, LiDAR depth"),
    ("APP", "Thermal + RAM Live Activity on the lock screen"),
    ("APP", "On-device AI scratchpad (Foundation Models)"),
]

struct IdeasView: View {
    var body: some View {
        Screen {
            Header(title: "MORE", sub: "tools + what's next")
            Panel {
                Text("GPS SPOOF").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                Text("Fake the phone's location. iOS only lets this run from the plugged-in Mac (it needs the developer tunnel), so GODMODE drives it from there:")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                Text("gm gps la      gm gps 34.05,-118.24      gm gps off")
                    .font(Theme.mono(12, .bold)).foregroundStyle(Theme.acid).textSelection(.enabled)
            }
            Header(title: "IDEAS", sub: "what's next")
            ForEach(IDEAS, id: \.1) { tag, idea in
                HStack(alignment: .top, spacing: 10) {
                    Text(tag).font(Theme.mono(10, .bold)).foregroundStyle(.black)
                        .frame(width: 46).padding(.vertical, 3).background(Theme.acid)
                    Text(idea).font(Theme.mono(13))
                }
            }
        }
    }
}
