import SwiftUI
import UIKit

// GODMODE — the on-phone half. The Mac `gm` CLI does the heavy lifting over USB;
// this app is the dashboard + speed lab + mod catalog you carry around.

enum Theme {
    static let bg = Color.black
    static let panel = Color(white: 0.07)
    static let line = Color(white: 0.16)
    static let acid = Color(red: 0.66, green: 1.0, blue: 0.2)
    static let dim = Color(white: 0.5)
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

@main
struct GodModeApp: App {
    @AppStorage("gm.speed") private var speed: Double = 1.0

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.acid)
                .onAppear { UISpeed.apply(speed); LaunchArgs.run() }
                .onChange(of: speed) { _, new in UISpeed.apply(new) }
        }
    }
}

/// `devicectl device process launch … com.orionjones.godmode --spoof 39.03,125.76` (or `--unspoof`)
/// drives the standalone spoof without touching the screen — used by `gm` and for testing.
enum LaunchArgs {
    @MainActor static func run() {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "--spoof"), i + 1 < a.count {
            let p = a[i + 1].split(separator: ",").compactMap { Double($0) }
            guard p.count == 2 else { return }
            UserDefaults.standard.set(true, forKey: "gm.geo.on")
            UserDefaults.standard.set("Remote", forKey: "gm.geo.name")
            Spoofer.shared.move(.init(latitude: p[0], longitude: p[1]), name: "Remote")
        } else if a.contains("--unspoof") {
            UserDefaults.standard.set(false, forKey: "gm.geo.on")
            Spoofer.shared.stop()
        } else if GeoSpoof.on, let (lat, lon) = GeoSpoof.coord {
            // App was killed (update, crash, reboot) while faking — pick up where it left off.
            Spoofer.shared.move(.init(latitude: lat, longitude: lon),
                                name: UserDefaults.standard.string(forKey: "gm.geo.name") ?? "Pin")
        }
    }
}

/// Scales every Core Animation clock in this app — same trick GodModeKit.dylib injects into patched apps.
enum UISpeed {
    static func apply(_ speed: Double) {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for w in ws.windows { w.layer.speed = Float(speed) }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            GPSView().tabItem { Label("GPS", systemImage: "location") }
            AIView().tabItem { Label("AI", systemImage: "sparkles") }
        }
    }
}

// MARK: - shared bits

struct Header: View {
    let title: String
    let sub: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("// \(sub)").font(Theme.mono(11)).foregroundStyle(Theme.dim)
            Text(title).font(Theme.mono(30, .bold)).foregroundStyle(Theme.acid)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.panel)
            .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
    }
}

struct Row: View {
    let k: String
    let v: String
    var hot = false
    var body: some View {
        HStack {
            Text(k).foregroundStyle(Theme.dim)
            Spacer()
            Text(v).foregroundStyle(hot ? Theme.acid : .white)
        }
        .font(Theme.mono(13))
    }
}

struct Screen<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}
