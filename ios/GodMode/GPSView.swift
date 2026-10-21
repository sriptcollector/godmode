import SwiftUI
import MapKit

// Pick any spot on a map and fake your location there.
//   • Whole phone incl. Snapchat: the phone can't move its *system* location alone (no jailbreak),
//     so the pin is POSTed to `gm gpsd` running on your plugged-in Mac, which drives it. You still
//     do everything from the phone; the Mac is just the relay.
//   • Native patched apps report the pin on-device via their own GODMODE menu → Fake GPS.

struct GPSPlace: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let lat: Double
    let lon: Double
}

let GPS_PLACES: [GPSPlace] = [
    .init(name: "San Francisco", lat: 37.7749, lon: -122.4194),
    .init(name: "New York", lat: 40.7128, lon: -74.0060),
    .init(name: "Miami", lat: 25.7617, lon: -80.1918),
    .init(name: "Las Vegas", lat: 36.1699, lon: -115.1398),
    .init(name: "London", lat: 51.5074, lon: -0.1278),
    .init(name: "Tokyo", lat: 35.6762, lon: 139.6503),
]

// Shared with WebEditor via UserDefaults — WebRules reads these to override geolocation in its web views.
enum GeoSpoof {
    static let d = UserDefaults.standard
    static var on: Bool { d.bool(forKey: "gm.geo.on") }
    static var coord: (Double, Double)? {
        guard on else { return nil }
        return (d.double(forKey: "gm.geo.lat"), d.double(forKey: "gm.geo.lon"))
    }
    static func set(_ lat: Double, _ lon: Double, name: String) {
        d.set(true, forKey: "gm.geo.on"); d.set(name, forKey: "gm.geo.name")
        d.set(lat, forKey: "gm.geo.lat"); d.set(lon, forKey: "gm.geo.lon")
    }
    static func off() { d.set(false, forKey: "gm.geo.on") }
}

struct GPSView: View {
    @AppStorage("gm.geo.on") private var on = false
    @AppStorage("gm.geo.name") private var name = ""
    @AppStorage("gm.geo.lat") private var lat = 37.7749
    @AppStorage("gm.geo.lon") private var lon = -122.4194
    @AppStorage("gm.gpsd.host") private var host = ""
    @AppStorage("gm.gpsd.token") private var token = ""
    @AppStorage("gm.gpsd.whole") private var wholePhone = false
    @State private var camera: MapCameraPosition = .automatic
    @State private var relay = ""
    @State private var showSetup = false

    private var pin: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    var body: some View {
        Screen {
            Header(title: "GPS", sub: on ? "faking: \(name)" : "real location")

            MapReader { proxy in
                Map(position: $camera) {
                    if on { Marker(name.isEmpty ? "here" : name, coordinate: pin).tint(Theme.acid) }
                }
                .frame(height: 300)
                .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
                .onTapGesture { pt in
                    if let c = proxy.convert(pt, from: .local) { drop(c, named: "Pin") }
                }
            }
            Text(on ? "faking \(fmt(lat)), \(fmt(lon)) — tap the map to move the pin"
                    : "tap anywhere on the map to drop a pin")
                .font(Theme.mono(11)).foregroundStyle(Theme.dim)

            // quick jumps
            let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(GPS_PLACES) { p in
                    Button(p.name) { drop(.init(latitude: p.lat, longitude: p.lon), named: p.name) }
                        .font(Theme.mono(11, .bold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(on && name == p.name ? Theme.acid : Theme.line)
                        .foregroundStyle(on && name == p.name ? .black : .white)
                }
            }

            if on {
                Button("stop faking — real location") { stop() }
                    .font(Theme.mono(13, .bold)).padding(.vertical, 9).frame(maxWidth: .infinity)
                    .background(Theme.panel).overlay(Rectangle().stroke(Theme.acid, lineWidth: 1))
                    .foregroundStyle(Theme.acid)
            }

            Panel {
                HStack {
                    Text("WHOLE PHONE (SNAPCHAT)").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                    Spacer()
                    Toggle("", isOn: $wholePhone).labelsHidden().tint(Theme.acid)
                }
                Text("On: the pin is sent to `gm gpsd` on your Mac, which moves your phone's real location (Snapchat, Maps, everything). Needs the Mac plugged in and running `gm gpsd`.")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
                Button(host.isEmpty ? "set Mac host + token" : "Mac: \(host)") { showSetup = true }
                    .font(Theme.mono(11)).foregroundStyle(Theme.acid)
                if !relay.isEmpty { Text(relay).font(Theme.mono(11)).foregroundStyle(Theme.dim) }
            }

            Panel {
                Text("NATIVE PATCHED APPS").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                Text("Open any `gm patch` app → three-finger double-tap → Fake GPS → pick a city. Runs fully on-device. (Snapchat bans modded clients, so use the Mac relay above for it instead.)")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
            }
        }
        .onAppear { if on { camera = .region(.init(center: pin, latitudinalMeters: 8000, longitudinalMeters: 8000)) } }
        .alert("Mac helper", isPresented: $showSetup) {
            TextField("host e.g. http://192.168.1.103:8777", text: $host)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("save") {}
            Button("cancel", role: .cancel) {}
        } message: {
            Text("Run `gm gpsd` on your Mac; it prints the host and token.")
        }
    }

    private func drop(_ c: CLLocationCoordinate2D, named n: String) {
        lat = c.latitude; lon = c.longitude; name = n; on = true
        GeoSpoof.set(c.latitude, c.longitude, name: n)
        camera = .region(.init(center: c, latitudinalMeters: 8000, longitudinalMeters: 8000))
        if wholePhone { relayPost("/set", body: ["lat": c.latitude, "lon": c.longitude]) }
    }

    private func stop() {
        on = false; GeoSpoof.off()
        if wholePhone { relayPost("/off", body: [:]) }
    }

    private func relayPost(_ path: String, body: [String: Any]) {
        guard !host.isEmpty, let url = URL(string: host + path + "?token=" + token) else {
            relay = "set the Mac host + token first"; return
        }
        relay = "sending to Mac…"
        var req = URLRequest(url: url); req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let ok = (resp as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                if let err { relay = "Mac unreachable: \(err.localizedDescription)" }
                else if ok { relay = path == "/off" ? "phone back to real GPS" : "phone moving (give it ~5s)" }
                else { relay = "Mac rejected it — check the token" }
            }
        }.resume()
    }

    private func fmt(_ d: Double) -> String { String(format: "%.4f", d) }
}
