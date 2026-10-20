import ActivityKit
import Combine
import Foundation

// Starts a Lock Screen / Dynamic Island Live Activity and refreshes it on a timer while the app
// is alive. iOS keeps showing the last pushed state after the app is backgrounded.
@MainActor
final class LiveActivityController: ObservableObject {
    @Published private(set) var running = false
    @Published var lastError: String?

    private var activity: Activity<GMActivityAttributes>?
    private var timer: AnyCancellable?

    var enabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start() {
        guard enabled else { lastError = "Turn on Live Activities in Settings › GODMODE."; return }
        guard activity == nil else { return }
        do {
            let content = ActivityContent(state: Telemetry.snapshot(), staleDate: nil)
            activity = try Activity.request(
                attributes: GMActivityAttributes(title: "GODMODE"),
                content: content,
                pushType: nil
            )
            running = true
            lastError = nil
            tick()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        let a = activity
        activity = nil
        running = false
        timer = nil
        Task { await a?.end(nil, dismissalPolicy: .immediate) }
    }

    private func tick() {
        timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            Task { await self?.push() }
        }
    }

    private func push() async {
        guard let activity else { return }
        await activity.update(ActivityContent(state: Telemetry.snapshot(), staleDate: Date().addingTimeInterval(60)))
    }
}
