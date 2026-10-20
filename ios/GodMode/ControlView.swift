import SwiftUI

#if canImport(FamilyControls)
import FamilyControls
import ManagedSettings
import DeviceActivity
#endif

// Phone-wide app control via Apple's Screen Time API — on-device, no jailbreak, no re-signing.
// Pick any apps/categories, then block them outright or cap them to N minutes a day. iOS shows its
// own shield screen over a blocked app. This is what Opal / one sec / ScreenZen are built on.
@MainActor
final class BlockModel: ObservableObject {
    @Published var authorized = false
    @Published var status = ""

    #if canImport(FamilyControls)
    @Published var selection = FamilyActivitySelection() {
        didSet { persist() }
    }
    private let store = ManagedSettingsStore(named: .init("godmode.block"))
    private let defaults = UserDefaults.standard

    init() { load(); refreshAuth() }

    var appCount: Int { selection.applicationTokens.count }
    var catCount: Int { selection.categoryTokens.count }

    func refreshAuth() {
        authorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    func authorize() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            refreshAuth()
            status = authorized ? "" : "Screen Time access denied."
        } catch {
            status = "Authorization failed: \(error.localizedDescription)"
        }
    }

    // Block the picked apps right now.
    func blockNow() {
        guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty else {
            status = "Pick some apps first."; return
        }
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
        status = "Blocked \(appCount) app\(appCount == 1 ? "" : "s")\(catCount > 0 ? " + \(catCount) categories" : ""). Shield shows when you open them."
    }

    func unblock() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        status = "Unblocked."
    }

    var isBlocking: Bool { store.shield.applications?.isEmpty == false || store.shield.applicationCategories != nil }

    private func persist() {
        if let data = try? JSONEncoder().encode(selection) { defaults.set(data, forKey: "gm.selection") }
    }
    private func load() {
        if let data = defaults.data(forKey: "gm.selection"),
           let s = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) { selection = s }
    }
    #else
    init() {}
    #endif
}

struct ControlView: View {
    @StateObject private var model = BlockModel()
    @State private var picking = false

    var body: some View {
        Screen {
            Header(title: "CONTROL", sub: "block & limit any app")
            #if canImport(FamilyControls)
            if !model.authorized {
                Panel {
                    Text("GODMODE uses Apple's Screen Time to block and limit apps across your whole phone. Grant access once.")
                        .font(Theme.mono(12)).foregroundStyle(Theme.dim)
                    Button("grant Screen Time access") { Task { await model.authorize() } }
                        .font(Theme.mono(14, .bold)).padding(.vertical, 8).frame(maxWidth: .infinity)
                        .background(Theme.acid).foregroundStyle(.black)
                }
            } else {
                Panel {
                    HStack {
                        Text("PICKED").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                        Spacer()
                        Text("\(model.appCount) apps · \(model.catCount) categories")
                            .font(Theme.mono(12)).foregroundStyle(.white)
                    }
                    Button("choose apps & categories") { picking = true }
                        .font(Theme.mono(14, .bold)).padding(.vertical, 8).frame(maxWidth: .infinity)
                        .background(Theme.line).foregroundStyle(.white)
                }
                Panel {
                    Text("BLOCK NOW").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                    HStack(spacing: 8) {
                        Button(model.isBlocking ? "blocking ✓" : "block") { model.blockNow() }
                            .font(Theme.mono(14, .bold)).padding(.vertical, 8).frame(maxWidth: .infinity)
                            .background(Theme.acid).foregroundStyle(.black)
                        Button("unblock") { model.unblock() }
                            .font(Theme.mono(14, .bold)).padding(.vertical, 8).frame(maxWidth: .infinity)
                            .background(Theme.line).foregroundStyle(.white)
                    }
                }
                Panel {
                    Text("DAILY LIMIT").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                    Text("Per-app time limits (use N min/day, then auto-block) are next — they need an App Group the signing key can't register yet.")
                        .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                }
            }
            if !model.status.isEmpty {
                Text(model.status).font(Theme.mono(11)).foregroundStyle(Theme.dim)
            }
            #else
            Panel { Text("Needs FamilyControls (iOS 16+).").font(Theme.mono(12)).foregroundStyle(Theme.dim) }
            #endif
        }
        #if canImport(FamilyControls)
        .familyActivityPicker(isPresented: $picking, selection: $model.selection)
        .onAppear { model.refreshAuth() }
        #endif
    }
}
