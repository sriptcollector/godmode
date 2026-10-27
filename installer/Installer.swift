// GPS Spoofer Installer: a one-button Mac app around install.sh (run with GM_UI=app).
// The script reports progress as `::step id text`, `::ok`, `::wait`, `::resume`, `::ask prompt\tdefault`,
// `::fail`, `::done` lines; answers and "I did it" taps go back on its stdin.
import AppKit
import SwiftUI

let scriptURL = URL(string: "https://godmode.orion-jones.com/install.sh")!

struct Step: Identifiable {
    let id: String
    let title: String
    let detail: String
}

let steps = [
    Step(id: "tools", title: "Developer tools", detail: "Homebrew and a few small helpers"),
    Step(id: "source", title: "Download GPS Spoofer", detail: "The latest version from GitHub"),
    Step(id: "xcode", title: "Xcode", detail: "Apple's free app builder"),
    Step(id: "signing", title: "Your Apple ID", detail: "Signs GPS Spoofer so your iPhone trusts it"),
    Step(id: "idevice", title: "Location engine", detail: "Lets GPS Spoofer move your GPS"),
    Step(id: "phone", title: "Your iPhone", detail: "Connected, trusted, Developer Mode on"),
    Step(id: "build", title: "Install on iPhone", detail: "Builds the app (a few minutes the first time)"),
    Step(id: "pair", title: "Pair", detail: "So it works without your Mac afterwards"),
]

enum Phase { case welcome, running, done, failed }
enum StepState { case pending, active, done }

@MainActor
final class Installer: ObservableObject {
    @Published var phase = Phase.welcome
    @Published var states: [String: StepState] = [:]
    @Published var waitMessage: String?
    @Published var askPrompt: String?
    @Published var answer = ""
    @Published var failure = ""
    @Published var log: [String] = []

    private var process: Process?
    private var input: FileHandle?
    private var activity: NSObjectProtocol?
    private var buffer = Data()

    func start() {
        phase = .running
        states = [:]
        waitMessage = nil
        askPrompt = nil
        failure = ""
        log = []
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled], reason: "Installing GPS Spoofer")
        Task {
            guard let script = await loadScript() else {
                fail("Couldn't download the installer. Check your internet connection and try again.")
                return
            }
            run(script)
        }
    }

    /// The latest script from the site, or the copy bundled in the app if that fails.
    private func loadScript() async -> URL? {
        if let test = ProcessInfo.processInfo.environment["GM_INSTALLER_SCRIPT"] {  // UI testing with a mock script
            return URL(fileURLWithPath: test)
        }
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("godmode-install.sh")
        if let (data, resp) = try? await URLSession.shared.data(from: scriptURL),
           (resp as? HTTPURLResponse)?.statusCode == 200, data.starts(with: Array("#!".utf8)),
           (try? data.write(to: dest)) != nil {
            return dest
        }
        return Bundle.main.url(forResource: "install", withExtension: "sh")
    }

    private func run(_ script: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [script.path]
        var env = ProcessInfo.processInfo.environment
        env["GM_UI"] = "app"
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        env["LANG"] = "en_US.UTF-8"
        p.environment = env
        let out = Pipe(), inp = Pipe()
        p.standardOutput = out
        p.standardError = out
        p.standardInput = inp
        input = inp.fileHandleForWriting
        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            Task { @MainActor in self?.consume(data) }
        }
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in self?.finished(proc.terminationStatus) }
        }
        do {
            try p.run()
            process = p
        } catch {
            fail("Couldn't start the installer: \(error.localizedDescription)")
        }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self)
            buffer.removeSubrange(buffer.startIndex...nl)
            handle(line)
        }
    }

    private func handle(_ raw: String) {
        let line = raw.replacingOccurrences(of: "\r", with: "")
        guard line.hasPrefix("::") else {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                log.append(line)
                if log.count > 2000 { log.removeFirst(log.count - 2000) }
            }
            return
        }
        let body = line.dropFirst(2)
        let kind = body.prefix { $0 != " " }
        let rest = String(body.dropFirst(kind.count)).trimmingCharacters(in: .whitespaces)
        switch kind {
        case "step":
            let id = String(rest.prefix { $0 != " " })
            for s in steps where states[s.id] == .active { states[s.id] = .done }
            states[id] = .active
            log.append("▸ \(rest.dropFirst(id.count).trimmingCharacters(in: .whitespaces))")
        case "ok":
            log.append("✓ \(rest)")
        case "wait":
            waitMessage = rest
            NSApp.requestUserAttention(.informationalRequest)
        case "resume":
            waitMessage = nil
        case "ask":
            let parts = rest.components(separatedBy: "\t")
            askPrompt = parts[0]
            answer = parts.count > 1 ? parts[1] : ""
            NSApp.requestUserAttention(.criticalRequest)
        case "fail":
            failure = rest
        case "done":
            for s in steps { states[s.id] = .done }
            phase = .done
        default:
            log.append(line)
        }
    }

    func send(_ text: String) {
        input?.write(Data((text + "\n").utf8))
    }

    func submitAnswer() {
        send(answer)
        askPrompt = nil
    }

    private func finished(_ status: Int32) {
        if let a = activity { ProcessInfo.processInfo.endActivity(a) }
        activity = nil
        process = nil
        waitMessage = nil
        askPrompt = nil
        if phase == .done { return }
        fail(failure.isEmpty ? "Something went wrong (exit code \(status)). The details below show where it stopped." : failure)
    }

    private func fail(_ message: String) {
        failure = message
        phase = .failed
    }

    func stop() { process?.terminate() }

    func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(log.joined(separator: "\n"), forType: .string)
    }
}

// MARK: - UI

let accent = Color(red: 0.25, green: 0.95, blue: 0.55)
let panel = Color.white.opacity(0.06)

struct ContentView: View {
    @EnvironmentObject var app: Installer

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.04, green: 0.06, blue: 0.08), Color(red: 0.02, green: 0.03, blue: 0.04)],
                           startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 0) {
                switch app.phase {
                case .welcome: Welcome()
                case .running: Running()
                case .done: Done()
                case .failed: Failed()
                }
            }
            .padding(32)
        }
        .frame(width: 560, height: 680)
        .preferredColorScheme(.dark)
    }
}

struct Logo: View {
    var size: CGFloat = 72
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [accent, Color(red: 0.1, green: 0.6, blue: 0.9)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: "location.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.black.opacity(0.85))
        }
        .frame(width: size, height: size)
        .shadow(color: accent.opacity(0.35), radius: 18)
    }
}

struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
    }
}

struct Welcome: View {
    @EnvironmentObject var app: Installer
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Logo(size: 96)
            VStack(spacing: 8) {
                Text("GPS Spoofer").font(.system(size: 34, weight: .heavy)).tracking(2)
                Text("Set your iPhone's location to anywhere in the world.\nNo jailbreak.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                Need(icon: "iphone", text: "Your iPhone and its cable")
                Need(icon: "person.crop.circle", text: "An Apple ID (a free one works)")
                Need(icon: "internaldrive", text: "About 40 GB free on this Mac")
                Need(icon: "clock", text: "Around an hour the first time, mostly waiting on Xcode")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Spacer()
            PrimaryButton(title: "Install GPS Spoofer") { app.start() }
            Text("You'll be guided through every step. Leave this window open.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct Need: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(accent)
            Text(text)
        }
    }
}

struct Running: View {
    @EnvironmentObject var app: Installer
    @State private var showLog = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Logo(size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Installing GPS Spoofer").font(.title2.bold())
                    Text("Keep this window open. Your Mac won't sleep while it works.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            if let msg = app.waitMessage {
                ActionCard(icon: "hand.point.up.left.fill", text: msg) {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Continues automatically when it's done").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button("I did it") { app.send("") }
                    }
                }
            } else if let prompt = app.askPrompt {
                ActionCard(icon: "questionmark.circle.fill", text: prompt) {
                    HStack {
                        TextField("", text: $app.answer).textFieldStyle(.roundedBorder).onSubmit { app.submitAnswer() }
                        Button("Continue") { app.submitAnswer() }.keyboardShortcut(.defaultAction)
                    }
                }
            }
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(steps) { s in StepRow(step: s, state: app.states[s.id] ?? .pending) }
                }
            }
            .frame(maxHeight: showLog ? 220 : .infinity)
            if showLog { LogView(lines: app.log) }
            HStack {
                Button(showLog ? "Hide details" : "Show details") { withAnimation { showLog.toggle() } }
                    .buttonStyle(.link)
                Spacer()
                Button("Cancel") { app.stop() }
            }
        }
    }
}

struct ActionCard<Content: View>: View {
    let icon: String
    let text: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.title2).foregroundStyle(accent)
                Text(text).font(.system(size: 14, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .padding(16)
        .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(accent.opacity(0.5)))
    }
}

struct StepRow: View {
    let step: Step
    let state: StepState
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(accent)
                case .active:
                    ProgressView().controlSize(.small)
                case .pending:
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
            .font(.title3)
            .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(step.title).font(.system(size: 14, weight: state == .active ? .semibold : .regular))
                    .foregroundStyle(state == .pending ? .secondary : .primary)
                Text(step.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(state == .active ? panel : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct LogView: View {
    let lines: [String]
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, l in
                        Text(l).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            .textSelection(.enabled).id(i)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            .onChange(of: lines.count) { n in proxy.scrollTo(n - 1, anchor: .bottom) }
        }
    }
}

struct Done: View {
    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 72)).foregroundStyle(accent)
            Text("GPS Spoofer is on your iPhone").font(.title.bold())
            VStack(alignment: .leading, spacing: 14) {
                Text("Two last steps on the phone").font(.headline)
                Numbered(n: 1, text: "Open the App Store, get **LocalDevVPN** (free), open it and tap **Connect**.")
                Numbered(n: 2, text: "Open **GPS Spoofer**, tap anywhere on the map, then tap **Teleport**.")
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("Keep LocalDevVPN connected while you use GPS Spoofer. With a free Apple ID the app stops opening after 7 days; just open this installer again to renew it.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            PrimaryButton(title: "Done") { NSApp.terminate(nil) }
        }
    }
}

struct Numbered: View {
    let n: Int
    let text: LocalizedStringKey
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                .frame(width: 22, height: 22).background(accent, in: Circle())
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct Failed: View {
    @EnvironmentObject var app: Installer
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 56)).foregroundStyle(.orange)
            Text("Installation stopped").font(.title.bold())
            Text(app.failure).multilineTextAlignment(.center).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LogView(lines: app.log)
            HStack {
                Button("Copy details") { app.copyLog() }
                Spacer()
                Button("Try again") { app.start() }.keyboardShortcut(.defaultAction)
            }
            Text("Trying again is safe: finished steps are skipped.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct GodmodeInstallerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var installer = Installer()
    var body: some Scene {
        WindowGroup("GPS Spoofer Installer") {
            ContentView().environmentObject(installer)
                .onAppear {  // mock-script runs start themselves so the UI can be screenshotted unattended
                    if ProcessInfo.processInfo.environment["GM_INSTALLER_SCRIPT"] != nil { installer.start() }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    installer.stop()
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
