import ActivityKit
import SwiftUI
import WidgetKit

@main
struct GodModeWidgetBundle: WidgetBundle {
    var body: some Widget {
        GodModeLiveActivity()
    }
}

private let acid = Color(red: 0.66, green: 1.0, blue: 0.2)
private func mono(_ s: CGFloat, _ w: Font.Weight = .regular) -> Font {
    .system(size: s, weight: w, design: .monospaced)
}

private func thermalColor(_ t: String) -> Color {
    switch t {
    case "serious", "critical": return .red
    case "fair": return .orange
    default: return acid
    }
}

struct GodModeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GMActivityAttributes.self) { context in
            // Lock screen / banner
            LockView(state: context.state)
                .padding(14)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(acid)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Stat(label: "THERMAL", value: s.thermal.uppercased(), color: thermalColor(s.thermal))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Stat(label: "BATTERY", value: s.battery < 0 ? "—" : "\(s.battery)%\(s.charging ? "⚡︎" : "")",
                         color: s.battery <= 20 && !s.charging ? .red : acid)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Stat(label: "RAM USED", value: "\(s.ramUsedMB) MB", color: .white)
                        Spacer()
                        Stat(label: "RAM FREE", value: "\(s.ramFreeMB) MB", color: .white)
                    }
                }
            } compactLeading: {
                Image(systemName: "bolt.horizontal.circle").foregroundStyle(thermalColor(s.thermal))
            } compactTrailing: {
                Text(s.battery < 0 ? "—" : "\(s.battery)%").font(mono(12, .bold)).foregroundStyle(acid)
            } minimal: {
                Image(systemName: "bolt.horizontal.circle").foregroundStyle(thermalColor(s.thermal))
            }
            .widgetURL(URL(string: "godmode://device"))
            .keylineTint(acid)
        }
    }
}

private struct Stat: View {
    let label: String
    let value: String
    var color: Color = .white
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(mono(9)).foregroundStyle(.gray)
            Text(value).font(mono(15, .bold)).foregroundStyle(color)
        }
    }
}

private struct LockView: View {
    let state: GMActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("GODMODE").font(mono(13, .bold)).foregroundStyle(acid)
                Spacer()
                Text(state.updated, style: .time).font(mono(10)).foregroundStyle(.gray)
            }
            HStack {
                Stat(label: "THERMAL", value: state.thermal.uppercased(), color: thermalColor(state.thermal))
                Spacer()
                Stat(label: "BATTERY", value: state.battery < 0 ? "—" : "\(state.battery)%\(state.charging ? " ⚡︎" : "")",
                     color: state.battery <= 20 && !state.charging ? .red : acid)
                Spacer()
                Stat(label: "RAM FREE", value: "\(state.ramFreeMB) MB", color: .white)
            }
        }
    }
}
