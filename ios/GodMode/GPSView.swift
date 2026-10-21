import SwiftUI

// Fake location, two ways, both on the phone:
//   • Edit tab (web apps): we override navigator.geolocation in the WKWebView — instant, this app only.
//   • Native apps you `gm patch`: open the app, GODMODE menu → Fake GPS, pick a city. That one app
//     reports the fake spot (GodModeKit swizzles CLLocationManager).
// System-wide spoofing still needs the cable (`gm gps <city>`), which drives all apps at once.

struct GPSPlace: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let lat: Double
    let lon: Double
}

let GPS_PLACES: [GPSPlace] = [
    .init(name: "San Francisco", lat: 37.7749, lon: -122.4194),
    .init(name: "Los Angeles", lat: 34.0522, lon: -118.2437),
    .init(name: "New York", lat: 40.7128, lon: -74.0060),
    .init(name: "Miami", lat: 25.7617, lon: -80.1918),
    .init(name: "Las Vegas", lat: 36.1699, lon: -115.1398),
    .init(name: "London", lat: 51.5074, lon: -0.1278),
    .init(name: "Paris", lat: 48.8566, lon: 2.3522),
    .init(name: "Tokyo", lat: 35.6762, lon: 139.6503),
]

// Shared with WebEditor via UserDefaults — WebRules reads these to override geolocation in its web views.
enum GeoSpoof {
    static let d = UserDefaults.standard
    static var on: Bool { d.bool(forKey: "gm.geo.on") }
    static var name: String { d.string(forKey: "gm.geo.name") ?? "" }
    static var coord: (Double, Double)? {
        guard on else { return nil }
        return (d.double(forKey: "gm.geo.lat"), d.double(forKey: "gm.geo.lon"))
    }
    static func set(_ p: GPSPlace) {
        d.set(true, forKey: "gm.geo.on"); d.set(p.name, forKey: "gm.geo.name")
        d.set(p.lat, forKey: "gm.geo.lat"); d.set(p.lon, forKey: "gm.geo.lon")
    }
    static func off() { d.set(false, forKey: "gm.geo.on") }
}

struct GPSView: View {
    @AppStorage("gm.geo.on") private var on = false
    @AppStorage("gm.geo.name") private var name = ""

    var body: some View {
        Screen {
            Header(title: "GPS", sub: on ? "faking: \(name)" : "real location")

            Panel {
                Text("WEB APPS (EDIT TAB)").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                Text("Pick a spot — every site in the Edit tab reports it instead of where you are. No computer.")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                let cols = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(GPS_PLACES) { p in
                        Button {
                            if on && name == p.name { GeoSpoof.off() } else { GeoSpoof.set(p) }
                        } label: {
                            Text((on && name == p.name ? "✓ " : "") + p.name)
                                .font(Theme.mono(12, .bold))
                                .frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(on && name == p.name ? Theme.acid : Theme.line)
                                .foregroundStyle(on && name == p.name ? .black : .white)
                        }
                    }
                }
                if on {
                    Button("stop faking — use real location") { GeoSpoof.off() }
                        .font(Theme.mono(13, .bold)).padding(.vertical, 8).frame(maxWidth: .infinity)
                        .background(Theme.panel).overlay(Rectangle().stroke(Theme.acid, lineWidth: 1))
                        .foregroundStyle(Theme.acid)
                }
            }

            Panel {
                Text("NATIVE APPS").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                Text("Open any app you ran `gm patch` on → three-finger double-tap → Fake GPS → pick a city. That app reports the fake spot (needs its location permission already granted).")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
            }

            Panel {
                Text("WHOLE PHONE").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                Text("System-wide spoofing drives every app at once but needs the cable: run `gm gps \(name.isEmpty ? "la" : name.lowercased())` on the Mac (`gm gps off` to clear). No jailbreak can make that standalone.")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
            }
        }
    }
}
