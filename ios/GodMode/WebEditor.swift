import SwiftUI
import WebKit

// GODMODE Web — runs Instagram (and other sites) inside the app and lets you edit the UI live.
// Tap "edit", tap anything on the page, it's hidden; rules are saved per site and re-applied on every
// load and on every in-app navigation. Presets kill Reels / Explore / Stories in one tap. Real login
// works because this is the normal web session — no re-signing, no integrity block, no computer.

struct Site: Identifiable, Hashable {
    let id: String
    let name: String
    let url: String
    let presets: [Preset]
    var defaultOn: [String] = []   // preset labels hidden out of the box
    var note: String? = nil
}

struct Preset: Identifiable, Hashable {
    var id: String { label }
    let label: String
    let css: String   // what it hides
}

let SITES: [Site] = [
    Site(id: "instagram", name: "Instagram", url: "https://www.instagram.com/", presets: [
        Preset(label: "Reels", css: """
        a[href*="/reels/"], a[href="#"][role="link"] svg[aria-label="Reels"],
        svg[aria-label="Reels"], [aria-label="Reels"] { display:none !important; }
        div[role="tablist"] a[href*="/reels/"] { display:none !important; }
        """),
        Preset(label: "Explore", css: """
        a[href="/explore/"], svg[aria-label="Explore"], [aria-label="Explore"] { display:none !important; }
        """),
        Preset(label: "Stories", css: """
        div[role="menu"][aria-label*="Stories"], [data-testid="stories-tray"] { display:none !important; }
        """),
        Preset(label: "Suggested", css: """
        div:has(> div > span:is([title="Suggested for you"])) { display:none !important; }
        """),
        Preset(label: "Suggested posts in feed", css: """
        article:has(span:is([title="Suggested for you"])),
        article:has(span:-webkit-any([title="Suggested for you"])),
        article:has(> div span:is([title="Suggested for you"])) { display:none !important; }
        """),
        Preset(label: "Threads badge", css: """
        a[href*="threads.net"], a[href*="/threads"], svg[aria-label*="Threads" i],
        [aria-label*="Threads" i] { display:none !important; }
        """),
    ], defaultOn: ["Reels", "Explore", "Suggested", "Suggested posts in feed", "Threads badge"]),
    Site(id: "tiktok", name: "TikTok", url: "https://www.tiktok.com/", presets: [
        Preset(label: "For You feed", css: """
        [data-e2e="nav-foryou"] { display:none !important; }
        """),
        Preset(label: "Explore", css: """
        [data-e2e="nav-explore"], a[href="/explore"] { display:none !important; }
        """),
        Preset(label: "LIVE", css: """
        [data-e2e="nav-live"], a[href*="/live"] { display:none !important; }
        """),
        Preset(label: "Shop", css: """
        [data-e2e="nav-shop"], a[href*="/shop"] { display:none !important; }
        """),
        Preset(label: "Friends", css: """
        [data-e2e="nav-friends"] { display:none !important; }
        """),
    ], defaultOn: ["For You feed", "Explore", "LIVE", "Shop"],
       note: "TikTok's whole point is the For-You feed; hiding it pushes you to Following. Your native TikTok GM (ASJTok) hides more inside the real app."),
    Site(id: "snapchat", name: "Snapchat", url: "https://web.snapchat.com/", presets: [
        Preset(label: "Stories", css: """
        [aria-label*="Stories" i], section:has(> h2:is([aria-label*="Stories" i])) { display:none !important; }
        """),
        Preset(label: "Spotlight", css: """
        [aria-label*="Spotlight" i], a[href*="spotlight"] { display:none !important; }
        """),
    ], defaultOn: ["Spotlight"],
       note: "Snapchat is a native-only app — web.snapchat.com is just chat/calling and has little Spotlight to hide. There's no clean no-jailbreak way to strip Spotlight from the real Snapchat app; Control can block Snapchat entirely."),
    Site(id: "youtube", name: "YouTube", url: "https://m.youtube.com/", presets: [
        Preset(label: "Shorts", css: """
        ytm-pivot-bar-item-renderer:has([aria-label*="Shorts" i]),
        ytm-rich-section-renderer:has(a[href*="/shorts"]),
        ytm-reel-shelf-renderer, [is-shorts] { display:none !important; }
        """),
    ], defaultOn: ["Shorts"]),
    Site(id: "reddit", name: "Reddit", url: "https://www.reddit.com/", presets: [
        Preset(label: "Recommended", css: """
        shreddit-feed [data-testid="recommendation"], faceplate-tracker[source="recommendation"] { display:none !important; }
        """),
    ]),
    Site(id: "x", name: "X", url: "https://x.com/", presets: [
        Preset(label: "For You tab", css: """
        [role="tablist"] [role="tab"]:first-child { display:none !important; }
        """),
        Preset(label: "Trends", css: """
        [aria-label="Timeline: Trending now"], [data-testid="sidebarColumn"] { display:none !important; }
        """),
    ]),
]

struct WebEditorView: View {
    @AppStorage("gm.web.site") private var siteID = "instagram"
    @StateObject private var store = WebRules()
    @State private var editing = false
    @State private var showSites = false
    @State private var showPresets = false
    @State private var reloadToken = 0

    private var site: Site { SITES.first { $0.id == siteID } ?? SITES[0] }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            WebContainer(site: site, store: store, editing: $editing, reloadToken: reloadToken)
                .ignoresSafeArea(edges: .bottom)
        }
        .background(Theme.bg.ignoresSafeArea())
        .confirmationDialog("Site", isPresented: $showSites, titleVisibility: .visible) {
            ForEach(SITES) { s in Button(s.name) { siteID = s.id } }
        }
        .confirmationDialog("Hide…", isPresented: $showPresets, titleVisibility: .visible) {
            ForEach(site.presets) { p in
                Button((store.hasPreset(site.id, p) ? "✓ " : "") + p.label) { store.togglePreset(site.id, p) }
            }
            if store.count(site.id) > 0 {
                Button("Clear all (\(store.count(site.id)))", role: .destructive) { store.clear(site.id) }
            }
        } message: {
            if let note = site.note { Text(note) }
        }
    }

    private var toolbar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("GODMODE").font(Theme.mono(13, .bold)).foregroundStyle(Theme.acid)
                Button(site.name + " ▾") { showSites = true }.font(Theme.mono(12)).foregroundStyle(.white)
                Spacer()
                Text("\(store.count(site.id)) hidden").font(Theme.mono(10)).foregroundStyle(Theme.dim)
            }
            HStack(spacing: 8) {
                tbtn(editing ? "DONE" : "✂︎ EDIT", editing) { editing.toggle() }
                tbtn("HIDE…", false) { showPresets = true }
                tbtn("↺", false) { reloadToken += 1 }
            }
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 10)
        .background(Theme.panel)
    }

    private func tbtn(_ t: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(t, action: action)
            .font(Theme.mono(13, .bold))
            .padding(.vertical, 8).frame(maxWidth: .infinity)
            .background(on ? Theme.acid : Theme.line)
            .foregroundStyle(on ? .black : .white)
    }
}

// Saved hide-rules per site: tapped CSS selectors + which presets are on.
final class WebRules: ObservableObject {
    @Published private var sel: [String: [String]] = [:]
    @Published private var presets: [String: Set<String>] = [:]
    private let d = UserDefaults.standard

    init() {
        sel = (d.dictionary(forKey: "gm.web.sel") as? [String: [String]]) ?? [:]
        if let raw = d.dictionary(forKey: "gm.web.presets") as? [String: [String]] {
            presets = raw.mapValues(Set.init)
        }
        seedDefaults()
    }

    // First time we ever see a site, turn its distraction presets on so it "just works".
    private func seedDefaults() {
        var seeded = Set(d.stringArray(forKey: "gm.web.seeded") ?? [])
        var changed = false
        for site in SITES where !seeded.contains(site.id) && !site.defaultOn.isEmpty {
            presets[site.id] = Set(site.defaultOn)
            seeded.insert(site.id); changed = true
        }
        if changed { savePresets(); d.set(Array(seeded), forKey: "gm.web.seeded") }
    }

    func selectors(_ site: String) -> [String] { sel[site] ?? [] }
    func count(_ site: String) -> Int { (sel[site]?.count ?? 0) + (presets[site]?.count ?? 0) }

    func add(_ site: String, _ selector: String) {
        var a = sel[site] ?? []
        guard !a.contains(selector) else { return }
        a.append(selector); sel[site] = a; saveSel()
    }
    func clear(_ site: String) { sel[site] = nil; presets[site] = nil; saveSel(); savePresets() }

    func hasPreset(_ site: String, _ p: Preset) -> Bool { presets[site]?.contains(p.label) ?? false }
    func togglePreset(_ site: String, _ p: Preset) {
        var s = presets[site] ?? []
        if s.contains(p.label) { s.remove(p.label) } else { s.insert(p.label) }
        presets[site] = s; savePresets()
    }
    func presetCSS(_ site: Site) -> String {
        let on = presets[site.id] ?? []
        return site.presets.filter { on.contains($0.label) }.map(\.css).joined(separator: "\n")
    }

    private func saveSel() { d.set(sel, forKey: "gm.web.sel") }
    private func savePresets() { d.set(presets.mapValues(Array.init), forKey: "gm.web.presets") }
}

// MARK: - WKWebView bridge

struct WebContainer: UIViewRepresentable {
    let site: Site
    @ObservedObject var store: WebRules
    @Binding var editing: Bool
    let reloadToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()          // persistent cookies → login sticks
        cfg.defaultWebpagePreferences.preferredContentMode = .mobile
        cfg.allowsInlineMediaPlayback = true       // keep video inline so it can't hijack fullscreen
        cfg.mediaTypesRequiringUserActionForPlayback = .all   // no autoplay doomscroll
        let ucc = WKUserContentController()
        ucc.add(context.coordinator, name: "gmHide")
        ucc.addUserScript(WKUserScript(source: Self.js, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        cfg.userContentController = ucc
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = context.coordinator
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        context.coordinator.web = web
        web.load(URLRequest(url: URL(string: site.url)!))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let c = context.coordinator
        if c.siteID != site.id {
            c.siteID = site.id
            web.load(URLRequest(url: URL(string: site.url)!))
        }
        if c.reloadToken != reloadToken { c.reloadToken = reloadToken; web.reload() }
        c.pushRules(editing: editing)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let parent: WebContainer
        weak var web: WKWebView?
        var siteID: String
        var reloadToken: Int
        init(_ p: WebContainer) { parent = p; siteID = p.site.id; reloadToken = p.reloadToken }

        func userContentController(_ u: WKUserContentController, didReceive m: WKScriptMessage) {
            guard m.name == "gmHide", let selector = m.body as? String, !selector.isEmpty else { return }
            parent.store.add(parent.site.id, selector)
        }

        func webView(_ w: WKWebView, didFinish n: WKNavigation!) { pushRules(editing: parent.editing) }

        // Hand the page the current hide-list + edit flag; the injected JS applies them and keeps
        // re-applying through the site's own SPA navigation.
        func pushRules(editing: Bool) {
            let selectors = parent.store.selectors(parent.site.id)
            let css = parent.store.presetCSS(parent.site)
            var data: [String: Any] = ["selectors": selectors, "css": css, "edit": editing]
            if let (lat, lon) = GeoSpoof.coord { data["geo"] = [lat, lon] }
            guard let json = try? JSONSerialization.data(withJSONObject: data),
                  let s = String(data: json, encoding: .utf8) else { return }
            web?.evaluateJavaScript("window.__gmApply(\(s));", completionHandler: nil)
        }

        static func == (a: Coordinator, b: Coordinator) -> Bool { a === b }
    }

    static let js = #"""
    (function () {
      if (window.__gmInit) return; window.__gmInit = true;
      var state = { selectors: [], css: "", edit: false };

      function styleEl() {
        var s = document.getElementById("gm-style");
        if (!s) { s = document.createElement("style"); s.id = "gm-style"; (document.head || document.documentElement).appendChild(s); }
        return s;
      }
      function apply() {
        var rules = state.selectors.map(function (x) { return x + "{display:none !important;}"; }).join("\n");
        styleEl().textContent = rules + "\n" + (state.css || "");
        document.documentElement.classList.toggle("gm-editing", !!state.edit);
      }
      window.__gmApply = function (s) { state = s; window.__gmGeo = s.geo || null; apply(); };

      // GPS spoof: when a fake coord is set, hand it to any site that asks navigator.geolocation.
      try {
        var geo = navigator.geolocation;
        if (geo && !geo.__gmWrapped) {
          var realGet = geo.getCurrentPosition && geo.getCurrentPosition.bind(geo);
          var realWatch = geo.watchPosition && geo.watchPosition.bind(geo);
          function fakePos() {
            var g = window.__gmGeo;
            return { coords: { latitude: g[0], longitude: g[1], accuracy: 20, altitude: 12,
              altitudeAccuracy: 5, heading: null, speed: null }, timestamp: Date.now() };
          }
          geo.getCurrentPosition = function (ok, err, opts) {
            if (window.__gmGeo) { try { ok(fakePos()); } catch (e) {} return; }
            return realGet ? realGet(ok, err, opts) : undefined;
          };
          geo.watchPosition = function (ok, err, opts) {
            if (window.__gmGeo) { try { ok(fakePos()); } catch (e) {} return 0; }
            return realWatch ? realWatch(ok, err, opts) : 0;
          };
          geo.__gmWrapped = true;
        }
      } catch (e) {}

      // Build a stable-ish CSS selector for a tapped element.
      function selectorFor(el) {
        if (!el || el === document.body) return null;
        if (el.id) return "#" + CSS.escape(el.id);
        var parts = [], node = el, depth = 0;
        while (node && node.nodeType === 1 && depth < 4 && node !== document.body) {
          var part = node.tagName.toLowerCase();
          var al = node.getAttribute && node.getAttribute("aria-label");
          if (al) { part += '[aria-label="' + al.replace(/"/g, '\\"') + '"]'; parts.unshift(part); break; }
          var href = node.getAttribute && node.getAttribute("href");
          if (href && href.length < 40) { part += '[href="' + href + '"]'; parts.unshift(part); break; }
          var cls = (node.className && node.className.baseVal !== undefined) ? node.className.baseVal : node.className;
          if (typeof cls === "string" && cls.trim()) {
            var c = cls.trim().split(/\s+/).slice(0, 2).map(function (x) { return "." + CSS.escape(x); }).join("");
            part += c;
          } else {
            var i = 1, sib = node; while ((sib = sib.previousElementSibling)) i++;
            part += ":nth-child(" + i + ")";
          }
          parts.unshift(part); node = node.parentElement; depth++;
        }
        return parts.join(" > ");
      }

      document.addEventListener("click", function (e) {
        if (!state.edit) return;
        e.preventDefault(); e.stopPropagation();
        var sel = selectorFor(e.target);
        if (sel) { try { window.webkit.messageHandlers.gmHide.postMessage(sel); } catch (x) {} }
      }, true);

      // Re-apply through the site's own re-renders (Instagram/YouTube are SPAs).
      var mo = new MutationObserver(function () { if (!document.getElementById("gm-style")) apply(); });
      try { mo.observe(document.documentElement, { childList: true, subtree: true }); } catch (x) {}
      setInterval(apply, 1000);

      var tag = document.createElement("style");
      tag.textContent = ".gm-editing, .gm-editing * { cursor: crosshair !important; }" +
        ".gm-editing *:hover { outline: 2px solid #a8ff33 !important; outline-offset: -2px; }";
      (document.head || document.documentElement).appendChild(tag);
      apply();
    })();
    """#
}
