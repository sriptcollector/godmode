import ActivityKit
import Foundation

// Shared between the app (which starts + updates the Live Activity) and the widget (which draws it).
// The app pushes a fresh ContentState on a timer; the widget just renders whatever it's handed, so
// no App Group / shared container is needed.

struct GMActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var thermal: String      // nominal / fair / serious / critical
        var battery: Int         // 0…100, -1 unknown
        var charging: Bool
        var ramUsedMB: Int       // this app's footprint
        var ramFreeMB: Int       // free system memory
        var updated: Date
    }

    var title: String            // "GODMODE"
}
