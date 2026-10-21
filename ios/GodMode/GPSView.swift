import SwiftUI
import MapKit

// Pick any spot on a map and fake your location there.
//   • Whole phone, standalone (default): OnDeviceGPS drives the phone's own developer location
//     service through LocalDevVPN — no Mac needed after the one-time `gm pairphone`.
//   • Whole phone via Mac (fallback): the pin is POSTed to `gm gpsd` on your Mac.
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
    .init(name: "Pyongyang", lat: 39.0392, lon: 125.7625),
    .init(name: "Paris", lat: 48.8566, lon: 2.3522),
    .init(name: "Sydney", lat: -33.8688, lon: 151.2093),
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
    @AppStorage("gm.gps.mode") private var mode = "phone"   // "phone" = standalone, "mac" = gpsd relay
    @ObservedObject private var device = OnDeviceGPS.shared
    @ObservedObject private var spoofer = Spoofer.shared
    @ObservedObject private var trip = TripEngine.shared
    @StateObject private var pois = POISearch()
    @State private var tool = "teleport"                      // "teleport" | "trip"
    @State private var camera: MapCameraPosition = .automatic
    @State private var picked: MKMapItem?
    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var showSetup = false
    @State private var visible: MKCoordinateRegion?

    private var pin: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }

    var body: some View {
        Screen {
            Header(title: "GPS", sub: trip.running ? "\(trip.mode.label.lowercased())ing · \(name)"
                                     : on ? "faking: \(name)" : "real location")

            Picker("", selection: $tool) {
                Text("Teleport").tag("teleport")
                Text("Trip").tag("trip")
            }.pickerStyle(.segmented)

            searchBar
            map
            if let p = picked { poiCard(p) }

            if tool == "teleport" { teleportPanel } else { tripPanel }

            backendPanel
        }
        .onAppear { if on { camera = .region(.init(center: pin, latitudinalMeters: 6000, longitudinalMeters: 6000)) } }
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

    // MARK: map

    private var map: some View {
        MapReader { proxy in
            Map(position: $camera) {
                if !trip.route.isEmpty {
                    MapPolyline(coordinates: trip.route).stroke(Theme.acid.opacity(0.8), lineWidth: 4)
                }
                ForEach(Array(trip.waypoints.enumerated()), id: \.element.id) { i, w in
                    Annotation(w.name, coordinate: w.coord) {
                        Text("\(i + 1)").font(Theme.mono(11, .bold)).foregroundStyle(.black)
                            .frame(width: 22, height: 22).background(Circle().fill(Theme.acid))
                    }
                }
                ForEach(pois.items, id: \.self) { m in
                    Annotation("", coordinate: m.placemark.coordinate) {
                        Button { picked = m } label: {
                            Image(systemName: POISearch.isHotel(m) ? "bed.double.fill" : "music.note")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(POISearch.isHotel(m) ? Color.blue : Color.pink))
                        }
                    }
                }
                if trip.running || trip.done > 0, let p = trip.position {
                    Annotation("", coordinate: p) {
                        Image(systemName: trip.mode.icon).font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black).frame(width: 30, height: 30)
                            .background(Circle().fill(Theme.acid))
                    }
                } else if on {
                    Marker(name.isEmpty ? "here" : name, coordinate: pin).tint(Theme.acid)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(height: 340)
            .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
            .onMapCameraChange(frequency: .onEnd) { ctx in
                visible = ctx.region
                pois.refresh(ctx.region)
            }
            .onTapGesture { pt in
                guard let c = proxy.convert(pt, from: .local) else { return }
                picked = nil
                if tool == "trip" { trip.add(c, name: "Point \(trip.waypoints.count + 1)") }
                else { teleport(c, named: "Pin") }
            }
        }
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("search a place, hotel, club…", text: $query)
                    .font(Theme.mono(13)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit { search() }
                Toggle(isOn: $pois.showHotels) { Image(systemName: "bed.double.fill") }
                    .toggleStyle(.button).tint(.blue)
                Toggle(isOn: $pois.showClubs) { Image(systemName: "music.note") }
                    .toggleStyle(.button).tint(.pink)
            }
            .padding(10).background(Theme.panel).overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
            .onChange(of: pois.showHotels) { _, _ in if let v = visible { pois.refresh(v) } }
            .onChange(of: pois.showClubs) { _, _ in if let v = visible { pois.refresh(v) } }
            ForEach(results, id: \.self) { m in
                Button {
                    results = []; query = ""; picked = m
                    camera = .region(.init(center: m.placemark.coordinate, latitudinalMeters: 3000, longitudinalMeters: 3000))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.name ?? "?").font(Theme.mono(12, .bold)).foregroundStyle(.white)
                        Text(m.placemark.title ?? "").font(Theme.mono(10)).foregroundStyle(Theme.dim).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func poiCard(_ m: MKMapItem) -> some View {
        Panel {
            HStack {
                Image(systemName: POISearch.isHotel(m) ? "bed.double.fill" : m.pointOfInterestCategory == .nightlife ? "music.note" : "mappin")
                    .foregroundStyle(Theme.acid)
                Text(m.name ?? "place").font(Theme.mono(13, .bold))
                Spacer()
                Button { picked = nil } label: { Image(systemName: "xmark") }.foregroundStyle(Theme.dim)
            }
            if let a = m.placemark.title { Text(a).font(Theme.mono(10)).foregroundStyle(Theme.dim).lineLimit(2) }
            HStack(spacing: 8) {
                bigButton("go here now") { teleport(m.placemark.coordinate, named: m.name ?? "Place"); picked = nil }
                bigButton("add to trip") {
                    tool = "trip"; trip.add(m.placemark.coordinate, name: m.name ?? "Stop"); picked = nil
                }
            }
        }
    }

    // MARK: teleport

    private var teleportPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(on ? "at \(fmt(lat)), \(fmt(lon)) — tap the map to jump" : "tap the map to jump there")
                .font(Theme.mono(11)).foregroundStyle(Theme.dim)
            let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(GPS_PLACES) { p in
                    Button(p.name) { teleport(.init(latitude: p.lat, longitude: p.lon), named: p.name) }
                        .font(Theme.mono(11, .bold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(on && name == p.name ? Theme.acid : Theme.line)
                        .foregroundStyle(on && name == p.name ? .black : .white)
                }
            }
            if on { bigButton("stop faking — real location", outline: true) { stopAll() } }
        }
    }

    // MARK: trip

    private var tripPanel: some View {
        Panel {
            Text("TRIP").font(Theme.mono(11)).foregroundStyle(Theme.dim)
            Picker("", selection: $trip.mode) {
                ForEach(TravelMode.allCases) { m in Label(m.label, systemImage: m.icon).tag(m) }
            }.pickerStyle(.segmented).disabled(trip.running)

            if trip.waypoints.isEmpty {
                Text("Tap the map, a hotel/club, or a search result to add waypoints. Drive follows real roads, walk follows footpaths, boat finds a real path through rivers, bays and sea. The route draws on the map before you start.")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
            }
            ForEach(Array(trip.waypoints.enumerated()), id: \.element.id) { i, w in
                HStack {
                    Text("\(i + 1)").font(Theme.mono(11, .bold)).foregroundStyle(.black)
                        .frame(width: 20, height: 20).background(Circle().fill(Theme.acid))
                    Text(w.name).font(Theme.mono(12)).lineLimit(1)
                    Spacer()
                    if !trip.running {
                        Button { trip.remove(w) } label: { Image(systemName: "minus.circle") }.foregroundStyle(Theme.dim)
                    }
                }
            }

            HStack {
                Text("TIME").font(Theme.mono(11)).foregroundStyle(Theme.dim)
                Picker("", selection: $trip.timeScale) {
                    Text("1×").tag(1.0); Text("2×").tag(2.0); Text("5×").tag(5.0); Text("20×").tag(20.0)
                }.pickerStyle(.segmented)
            }
            Text("1× = real-life speed (most realistic; apps that check travel speed won't flag it).")
                .font(Theme.mono(10)).foregroundStyle(Theme.dim)

            if trip.total > 0 {
                ProgressView(value: trip.done, total: trip.total).tint(Theme.acid)
                Text(String(format: "%.2f / %.2f km · %.0f km/h · ~%@ left",
                            trip.done / 1000, trip.total / 1000, trip.speed * 3.6, eta(trip.etaSeconds)))
                    .font(Theme.mono(11)).foregroundStyle(Theme.acid)
            }
            if !trip.message.isEmpty { Text(trip.message).font(Theme.mono(11)).foregroundStyle(Theme.dim) }

            HStack(spacing: 8) {
                if trip.running {
                    bigButton("pause") { trip.pause() }
                } else {
                    bigButton(trip.planning ? "planning…" : trip.done > 0 && trip.done < trip.total ? "resume" : "start trip") {
                        Task {
                            await trip.start()
                            if let first = trip.route.first, trip.done == 0 {
                                camera = .region(.init(center: first, latitudinalMeters: 4000, longitudinalMeters: 4000))
                            }
                        }
                    }.disabled(trip.waypoints.count < 2 || trip.planning)
                }
                bigButton("clear", outline: true) { trip.clearAll() }
            }
            if on && !trip.running { bigButton("stop faking — real location", outline: true) { stopAll() } }
        }
    }

    // MARK: backend

    private var backendPanel: some View {
        Panel {
            Text("WHOLE PHONE").font(Theme.mono(11)).foregroundStyle(Theme.dim)
            Picker("", selection: $mode) {
                Text("on-phone (no Mac)").tag("phone")
                Text("via Mac").tag("mac")
            }.pickerStyle(.segmented)
            if mode == "phone" {
                HStack(spacing: 6) {
                    Circle().fill(device.live ? Theme.acid : Theme.dim).frame(width: 8, height: 8)
                    Text(device.status).font(Theme.mono(11)).foregroundStyle(device.live ? Theme.acid : Theme.dim)
                }
                Text(OnDeviceGPS.hasPairing
                     ? "Moves the real location for every app. Keep LocalDevVPN connected + Wi-Fi on. Leave GODMODE in the background — swiping it away snaps you back."
                     : "Not paired yet: run `gm pairphone` on the Mac once, and install LocalDevVPN from the App Store.")
                    .font(Theme.mono(11)).foregroundStyle(Theme.dim)
            } else {
                Toggle(isOn: $wholePhone) { Text("send to `gm gpsd` on Mac").font(Theme.mono(11)) }.tint(Theme.acid)
                Button(host.isEmpty ? "set Mac host + token" : "Mac: \(host)") { showSetup = true }
                    .font(Theme.mono(11)).foregroundStyle(Theme.acid)
                if !spoofer.relayStatus.isEmpty {
                    Text(spoofer.relayStatus).font(Theme.mono(11)).foregroundStyle(Theme.dim)
                }
            }
        }
    }

    // MARK: actions

    private func teleport(_ c: CLLocationCoordinate2D, named n: String) {
        if trip.running { trip.pause() }
        lat = c.latitude; lon = c.longitude; name = n; on = true
        camera = .region(.init(center: c, latitudinalMeters: 6000, longitudinalMeters: 6000))
        Spoofer.shared.move(c, name: n)
    }

    private func stopAll() {
        trip.stop(); on = false
        Spoofer.shared.stop()
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { results = []; return }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = q
        if let v = visible { req.region = v }
        Task { results = Array(((try? await MKLocalSearch(request: req).start().mapItems) ?? []).prefix(6)) }
    }

    private func bigButton(_ t: String, outline: Bool = false, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(t).font(Theme.mono(13, .bold)).padding(.vertical, 10).frame(maxWidth: .infinity)
                .background(outline ? Theme.panel : Theme.acid)
                .overlay(Rectangle().stroke(Theme.acid, lineWidth: 1))
                .foregroundStyle(outline ? Theme.acid : .black)
        }
    }

    private func eta(_ s: Double) -> String {
        let m = Int(s / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(max(m, 1))m"
    }

    private func fmt(_ d: Double) -> String { String(format: "%.4f", d) }
}
