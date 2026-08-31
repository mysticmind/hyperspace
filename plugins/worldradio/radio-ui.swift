// The globe, on Super+Shift+R. Built on first run by radio-panel.
//
// This owns no state and knows no API. Every question it asks - what is on the
// globe, what is playing, what is a favourite - goes to the `radio` CLI next
// to it, so the panel, the menu bar and the keybindings all read the same
// cache and write the same state file. The panel is a view, not a second
// implementation.
//
// Same shape as bin/plugin-ui.swift: no .app bundle, no Info.plist, no
// signing. AppKit makes the window by hand and hosts a SwiftUI view in it,
// which is what works for a bare binary compiled into a cache directory.
//
// Keyboard first, for the same reason as the other panels: it is summoned by a
// chord, so needing the mouse to tune would defeat the point. The globe is the
// exception and is unashamedly a mouse toy - drag it, spin it, click a dot.
import AppKit
import Combine
import SwiftUI

// MARK: - talking to the CLI

let radioCmd = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""
let worldPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""

@discardableResult
func radio(_ args: [String]) -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: radioCmd)
    process.arguments = args
    let output = Pipe()
    process.standardOutput = output
    process.standardError = Pipe()
    do { try process.run() } catch { return Data() }
    // Read before waiting: a station list is bigger than a pipe buffer, and
    // waitUntilExit() with a full pipe deadlocks both processes forever.
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return data
}

func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
    try? JSONDecoder().decode(type, from: data)
}

// MARK: - what the CLI returns

struct Station: Codable, Identifiable, Equatable {
    var uuid = ""
    var name = ""
    var country = ""
    var cc = ""
    var lat: Double?
    var lon: Double?
    var tags = ""
    var bitrate = 0
    var id: String { uuid }
    var isEmpty: Bool { uuid.isEmpty }

    init() {}

    // Hand-written so a missing or null field is a default rather than a
    // decode failure. `radio status` returns "station": {} when nothing is
    // playing, and lat/lon are null for most of the directory - the
    // synthesised initialiser would throw on every one of those.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uuid = (try? c.decode(String.self, forKey: .uuid)) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        country = (try? c.decode(String.self, forKey: .country)) ?? ""
        cc = (try? c.decode(String.self, forKey: .cc)) ?? ""
        lat = try? c.decode(Double.self, forKey: .lat)
        lon = try? c.decode(Double.self, forKey: .lon)
        tags = (try? c.decode(String.self, forKey: .tags)) ?? ""
        bitrate = (try? c.decode(Int.self, forKey: .bitrate)) ?? 0
    }
}

struct WorldStations: Codable {
    var stations: [Station] = []
    var partial = false
}

struct Status: Codable {
    var running = false
    var playing = false
    var paused = false
    var buffering = false
    var muted = false
    var title = ""
    var volume = 70
    var station = Station()
    var favorite = false
    var mpv = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        running = (try? c.decode(Bool.self, forKey: .running)) ?? false
        playing = (try? c.decode(Bool.self, forKey: .playing)) ?? false
        paused = (try? c.decode(Bool.self, forKey: .paused)) ?? false
        buffering = (try? c.decode(Bool.self, forKey: .buffering)) ?? false
        muted = (try? c.decode(Bool.self, forKey: .muted)) ?? false
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        volume = (try? c.decode(Int.self, forKey: .volume)) ?? 70
        station = (try? c.decode(Station.self, forKey: .station)) ?? Station()
        favorite = (try? c.decode(Bool.self, forKey: .favorite)) ?? false
        mpv = (try? c.decode(String.self, forKey: .mpv)) ?? ""
    }
}

// The bundled map. Rings are flat [lon, lat, lon, lat, ...] - see world-build.
struct Country: Codable, Identifiable {
    let c: String
    let n: String
    let o: [Double]
    let p: [[Double]]
    var id: String { c }
}

struct WorldMap: Codable {
    var countries: [Country] = []
}

// MARK: - orthographic projection
//
// The globe is a real orthographic projection rather than a picture of one:
// the same maths places the coastlines and the station dots, so a dot is
// where the transmitter is and clicking empty ocean lands in the ocean.

/// The panel's fixed geometry, in one place because two different coordinate
/// systems need it: SwiftUI lays the views out with these, and the AppKit
/// scroll monitor has to know where the globe is to tell a zoom from someone
/// scrolling the station list.
///
/// It reads the numbers rather than asking SwiftUI, because SwiftUI's answer
/// is in the wrong space: `geometry.frame(in: .global)` inside a bare
/// NSHostingView is CENTRE-origin, so the globe reports itself at
/// (-480.5, -315) while an AppKit event arrives at (300, 268) from the top
/// left. Comparing the two silently missed every time, and scroll-to-zoom did
/// nothing at all. Measured on macOS 26.
enum Layout {
    static let globeWidth: CGFloat = 620
    static let globeHeight: CGFloat = 560
    static let sidebarWidth: CGFloat = 340
    static let dividerWidth: CGFloat = 1
    static let panelWidth = globeWidth + dividerWidth + sidebarWidth
    static let panelHeight: CGFloat = 660

    /// Where the globe is in the content view's own top-left-origin space.
    static let globeRect = CGRect(x: 0, y: 0, width: globeWidth, height: globeHeight)
}

/// 1 is the whole disc in the panel; 9 is close enough to pick one dot out of
/// a city. Below 0.85 the globe is a marble with nothing readable on it.
let MIN_ZOOM = 0.85
let MAX_ZOOM = 9.0

struct Globe {
    var lon = 10.0          // longitude at the centre of the disc
    var lat = 25.0          // latitude at the centre
    var zoom = 1.0
    var size = CGSize(width: 640, height: 640)

    var radius: CGFloat { min(size.width, size.height) / 2 * 0.92 * zoom }
    var centre: CGPoint { CGPoint(x: size.width / 2, y: size.height / 2) }

    /// Screen point for a coordinate, or nil when it is round the back.
    func project(_ longitude: Double, _ latitude: Double) -> CGPoint? {
        let φ = latitude * .pi / 180, λ = longitude * .pi / 180
        let φ0 = lat * .pi / 180, λ0 = lon * .pi / 180
        let cosc = sin(φ0) * sin(φ) + cos(φ0) * cos(φ) * cos(λ - λ0)
        guard cosc >= 0 else { return nil }
        let x = cos(φ) * sin(λ - λ0)
        let y = cos(φ0) * sin(φ) - sin(φ0) * cos(φ) * cos(λ - λ0)
        // Y is negated because AppKit's canvas grows downwards and the globe
        // does not.
        return CGPoint(x: centre.x + CGFloat(x) * radius,
                       y: centre.y - CGFloat(y) * radius)
    }

    /// The coordinate under a screen point, or nil when it missed the disc.
    func unproject(_ point: CGPoint) -> (lon: Double, lat: Double)? {
        let x = Double(point.x - centre.x) / Double(radius)
        let y = Double(centre.y - point.y) / Double(radius)
        let ρ = (x * x + y * y).squareRoot()
        guard ρ <= 1 else { return nil }
        let c = asin(ρ)
        let φ0 = lat * .pi / 180, λ0 = lon * .pi / 180
        // ρ == 0 is the exact centre of the disc, where the general formula
        // divides by zero. It is also simply the point being looked at.
        if ρ < 1e-9 { return (lon, lat) }
        let φ = asin(cos(c) * sin(φ0) + y * sin(c) * cos(φ0) / ρ)
        let λ = λ0 + atan2(x * sin(c), ρ * cos(c) * cos(φ0) - y * sin(c) * sin(φ0))
        var degrees = λ * 180 / .pi
        while degrees > 180 { degrees -= 360 }
        while degrees < -180 { degrees += 360 }
        return (degrees, φ * 180 / .pi)
    }
}

// MARK: - the model

enum Source: String, CaseIterable {
    case search = "Search"
    case favorites = "Favourites"
    case recent = "Recent"
    case country = "Country"
}

final class Model: ObservableObject {
    @Published var globe = Globe()
    @Published var map = WorldMap()
    @Published var stations: [Station] = []
    @Published var partial = false
    @Published var status = Status()
    @Published var list: [Station] = []
    @Published var source: Source = .favorites
    @Published var countryName = ""
    @Published var query = ""
    @Published var selection = 0
    @Published var hovered: Station?
    @Published var note: String?
    @Published var loading = true
    @Published var dragging = false
    private var poll: Timer?

    init() {
        if let data = FileManager.default.contents(atPath: worldPath),
           let loaded = decode(WorldMap.self, data) {
            map = loaded
        }
        refreshStatus()
        showFavorites()
        loadWorld()
        // Two seconds is the ICY metadata cadence in practice: any faster and
        // the song title still has not changed, any slower and it lags the
        // music. It also picks up a stream that finished buffering.
        poll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshStatus()
            self?.fillWorldIfPartial()
        }
    }

    // MARK: data

    func loadWorld() {
        DispatchQueue.global().async {
            let payload = decode(WorldStations.self, radio(["world"])) ?? WorldStations()
            DispatchQueue.main.async {
                self.stations = payload.stations
                self.partial = payload.partial
                self.loading = false
                if payload.stations.isEmpty {
                    self.note = "No stations. Is this machine online?"
                }
            }
        }
    }

    /// The CLI fetches the rest of the world in the background, so the panel
    /// asks again until it stops saying "partial" and the globe fills in.
    private func fillWorldIfPartial() {
        guard partial else { return }
        DispatchQueue.global().async {
            let payload = decode(WorldStations.self, radio(["world"])) ?? WorldStations()
            DispatchQueue.main.async {
                guard payload.stations.count > self.stations.count || !payload.partial
                else { return }
                self.stations = payload.stations
                self.partial = payload.partial
            }
        }
    }

    func refreshStatus() {
        DispatchQueue.global().async {
            let fresh = decode(Status.self, radio(["status"])) ?? Status()
            DispatchQueue.main.async { self.status = fresh }
        }
    }

    // MARK: playback

    func play(_ station: Station) {
        guard !station.isEmpty else { return }
        note = "Tuning \(station.name)..."
        DispatchQueue.global().async {
            let data = radio(["play", station.uuid])
            let fresh = decode(Status.self, data)
            DispatchQueue.main.async {
                if let fresh {
                    self.status = fresh
                    self.note = nil
                } else {
                    self.note = self.errorText(data) ?? "Could not tune that station"
                }
            }
        }
    }

    func toggle() { act(["toggle"]) }
    func random() { note = "Tuning..."; act(["random"]) }
    func stop() { act(["stop"]) }
    func volume(_ delta: Int) { act(["volume", delta > 0 ? "+\(delta)" : "\(delta)"]) }
    func mute() { act(["mute"]) }

    func favorite() {
        guard !status.station.isEmpty else {
            note = "Nothing is playing"
            return
        }
        DispatchQueue.global().async {
            _ = radio(["favorite"])
            let fresh = decode(Status.self, radio(["status"])) ?? Status()
            DispatchQueue.main.async {
                self.status = fresh
                self.note = fresh.favorite ? "Added to favourites" : "Removed from favourites"
                if self.source == .favorites { self.showFavorites() }
            }
        }
    }

    private func act(_ args: [String]) {
        DispatchQueue.global().async {
            let data = radio(args)
            let fresh = decode(Status.self, data)
            DispatchQueue.main.async {
                if let fresh {
                    self.status = fresh
                    self.note = nil
                } else {
                    self.note = self.errorText(data)
                }
            }
        }
    }

    private func errorText(_ data: Data) -> String? {
        struct Failure: Codable { let error: String }
        return decode(Failure.self, data)?.error
    }

    // MARK: the list beside the globe

    func showFavorites() {
        source = .favorites
        countryName = ""
        fill(["favorites"])
    }

    func showRecent() {
        source = .recent
        countryName = ""
        fill(["recent"])
    }

    func showSearch() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        source = .search
        countryName = ""
        fill(["search", text])
    }

    func showCountry(_ code: String, _ name: String) {
        source = .country
        countryName = name
        fill(["country", code])
    }

    private func fill(_ args: [String]) {
        loading = true
        DispatchQueue.global().async {
            let found = decode([Station].self, radio(args)) ?? []
            DispatchQueue.main.async {
                self.list = found
                self.selection = 0
                self.loading = false
                if found.isEmpty && self.source != .favorites {
                    self.note = "Nothing found"
                }
            }
        }
    }

    // MARK: the globe

    func spin(to station: Station) {
        guard let lon = station.lon, let lat = station.lat else { return }
        spin(toLon: lon, lat: lat)
    }

    func spin(toLon lon: Double, lat: Double) {
        // Animated, because a globe that teleports gives no sense of where it
        // went. A quarter second is long enough to follow and short enough not
        // to be in the way.
        withAnimation(.easeInOut(duration: 0.35)) {
            globe.lon = lon
            globe.lat = lat
        }
    }

    /// Zoom by a number of steps, where a step is one wheel notch.
    ///
    /// Multiplicative, so a notch feels the same at every zoom - additive zoom
    /// crawls when you are close and jumps when you are far out. 1.18 per step
    /// puts the whole range about thirteen notches apart, which is a flick of
    /// the wheel rather than a scroll session: the first version moved 3% per
    /// notch and read as nothing happening at all.
    func zoom(steps: Double) {
        setZoom(globe.zoom * pow(1.18, steps))
    }

    /// For the buttons and the keys, which want one deliberate jump each.
    func zoom(times factor: Double) {
        withAnimation(.easeOut(duration: 0.18)) { setZoom(globe.zoom * factor) }
    }

    private func setZoom(_ value: Double) {
        globe.zoom = min(max(value, MIN_ZOOM), MAX_ZOOM)
    }

    var canZoomIn: Bool { globe.zoom < MAX_ZOOM - 0.001 }
    var canZoomOut: Bool { globe.zoom > MIN_ZOOM + 0.001 }

    /// Back to the whole world, pointing at where it started.
    func resetGlobe() {
        withAnimation(.easeInOut(duration: 0.3)) {
            globe = Globe(lon: 10, lat: 25, zoom: 1, size: globe.size)
        }
    }

    func move(_ delta: Int) {
        guard !list.isEmpty else { return }
        selection = min(max(selection + delta, 0), list.count - 1)
    }

    var selected: Station? {
        list.indices.contains(selection) ? list[selection] : nil
    }

    /// Nearest station dot to a screen point, if one is close enough to have
    /// been aimed at. 9 points is roughly a fingertip at this dot size.
    func station(near point: CGPoint) -> Station? {
        var best: (Station, CGFloat)?
        for station in stations {
            guard let lon = station.lon, let lat = station.lat,
                  let at = globe.project(lon, lat) else { continue }
            let distance = hypot(at.x - point.x, at.y - point.y)
            if distance < 9 && (best == nil || distance < best!.1) {
                best = (station, distance)
            }
        }
        return best?.0
    }

    /// The country under a screen point, by ray casting against the same
    /// polygons that were drawn.
    func country(at point: CGPoint) -> Country? {
        guard let where_ = globe.unproject(point) else { return nil }
        for country in map.countries {
            for ring in country.p where contains(ring, where_.lon, where_.lat) {
                return country
            }
        }
        return nil
    }

    private func contains(_ ring: [Double], _ lon: Double, _ lat: Double) -> Bool {
        var inside = false
        let count = ring.count / 2
        guard count > 2 else { return false }
        var j = count - 1
        for i in 0..<count {
            let xi = ring[i * 2], yi = ring[i * 2 + 1]
            let xj = ring[j * 2], yj = ring[j * 2 + 1]
            if (yi > lat) != (yj > lat),
               lon < (xj - xi) * (lat - yi) / (yj - yi) + xi {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}

// MARK: - the globe view

struct GlobeView: View {
    @ObservedObject var model: Model
    @Environment(\.colorScheme) private var scheme

    private var ocean: Color {
        scheme == .dark ? Color(white: 0.13) : Color(white: 0.93)
    }
    private var land: Color {
        scheme == .dark ? Color(white: 0.26) : Color(white: 0.82)
    }
    private var coast: Color {
        scheme == .dark ? Color(white: 0.42) : Color(white: 0.66)
    }
    private var grid: Color {
        (scheme == .dark ? Color.white : Color.black).opacity(0.06)
    }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                var globe = model.globe
                globe.size = size
                draw(context, globe, size)
            }
            .contentShape(Rectangle())
            .gesture(drag)
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    // Not while dragging: the pointer is nailed to the globe
                    // and every station under it would flicker a label.
                    model.hovered = model.dragging ? nil : model.station(near: point)
                case .ended:
                    model.hovered = nil
                }
            }
            .onTapGesture { point in tap(point) }
            .onAppear { model.globe.size = geometry.size }
            .onChange(of: geometry.size) { _ in model.globe.size = geometry.size }
            // Scroll and pinch both zoom, but neither is visible, and a
            // control you cannot see is one you do not know you have. These
            // are also the only way in on a mouse with no wheel.
            .overlay(alignment: .bottomLeading) { zoomControls }
        }
    }

    private var zoomControls: some View {
        VStack(spacing: 6) {
            zoomButton("plus", "Zoom in", enabled: model.canZoomIn) {
                model.zoom(times: 1.6)
            }
            zoomButton("minus", "Zoom out", enabled: model.canZoomOut) {
                model.zoom(times: 1 / 1.6)
            }
            zoomButton("arrow.counterclockwise", "Whole world", enabled: true) {
                model.resetGlobe()
            }
        }
        .padding(14)
    }

    private func zoomButton(_ symbol: String, _ help: String, enabled: Bool,
                            _ action: @escaping () -> Void) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .frame(width: 24, height: 24)
            // Against the ocean in either appearance, which is why this is a
            // material rather than a fixed grey.
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
            .help(help)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                model.dragging = true
                // Degrees per point, scaled by zoom so the surface under the
                // pointer keeps up when zoomed in rather than racing away.
                let k = 0.32 / model.globe.zoom
                let previous = value.translation
                let last = lastTranslation ?? .zero
                model.globe.lon -= Double(previous.width - last.width) * k
                model.globe.lat += Double(previous.height - last.height) * k
                model.globe.lat = min(max(model.globe.lat, -89), 89)
                while model.globe.lon > 180 { model.globe.lon -= 360 }
                while model.globe.lon < -180 { model.globe.lon += 360 }
                lastTranslation = previous
            }
            .onEnded { _ in
                lastTranslation = nil
                model.dragging = false
            }
    }

    // Drag deltas arrive as a running total from the gesture's start, so the
    // previous total has to be kept to turn them back into per-frame moves.
    @State private var lastTranslation: CGSize?

    private func tap(_ point: CGPoint) {
        if let station = model.station(near: point) {
            model.play(station)
            return
        }
        if let country = model.country(at: point) {
            model.showCountry(country.c, country.n)
            model.spin(toLon: country.o[0], lat: country.o[1])
        }
    }

    private func draw(_ context: GraphicsContext, _ globe: Globe, _ size: CGSize) {
        let centre = globe.centre
        let radius = globe.radius

        // The disc itself. Everything else is clipped to it by the projection,
        // which returns nil for the far side.
        let disc = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                          width: radius * 2, height: radius * 2))
        context.fill(disc, with: .color(ocean))

        drawGraticule(context, globe)

        for country in model.map.countries {
            for ring in country.p {
                let path = ringPath(ring, globe)
                guard !path.isEmpty else { continue }
                context.fill(path, with: .color(land))
                context.stroke(path, with: .color(coast), lineWidth: 0.6)
            }
        }

        context.stroke(disc, with: .color(coast.opacity(0.7)), lineWidth: 0.8)

        drawStations(context, globe)
    }

    private func drawGraticule(_ context: GraphicsContext, _ globe: Globe) {
        var path = Path()
        for meridian in stride(from: -180.0, to: 180.0, by: 30) {
            appendLine(&path, globe, (-80.0).stride(to: 80, by: 4).map { (meridian, $0) })
        }
        for parallel in stride(from: -60.0, through: 60.0, by: 30) {
            appendLine(&path, globe, (-180.0).stride(to: 180, by: 4).map { ($0, parallel) })
        }
        context.stroke(path, with: .color(grid), lineWidth: 0.5)
    }

    private func appendLine(_ path: inout Path, _ globe: Globe, _ points: [(Double, Double)]) {
        var started = false
        for (lon, lat) in points {
            guard let at = globe.project(lon, lat) else { started = false; continue }
            if started { path.addLine(to: at) } else { path.move(to: at); started = true }
        }
    }

    /// One ring, broken wherever it goes over the horizon.
    private func ringPath(_ ring: [Double], _ globe: Globe) -> Path {
        var path = Path()
        var started = false
        var count = 0
        let points = ring.count / 2
        for i in 0..<points {
            guard let at = globe.project(ring[i * 2], ring[i * 2 + 1]) else {
                started = false
                continue
            }
            if started { path.addLine(to: at) } else { path.move(to: at); started = true }
            count += 1
        }
        // A two-point fragment is a hairline on the limb, not a country.
        return count > 2 ? path : Path()
    }

    private func drawStations(_ context: GraphicsContext, _ globe: Globe) {
        let current = model.status.station.uuid
        // 3000 dots is fine to draw and not fine to draw sixty times a second
        // while a drag is in flight. The list arrives ordered by popularity,
        // so the prefix is the meaningful half rather than an arbitrary one.
        let shown = model.dragging && model.stations.count > 900
            ? Array(model.stations.prefix(900))
            : model.stations

        var dots = Path()
        for station in shown {
            guard let lon = station.lon, let lat = station.lat,
                  let at = globe.project(lon, lat), station.uuid != current else { continue }
            dots.addEllipse(in: CGRect(x: at.x - 1.6, y: at.y - 1.6, width: 3.2, height: 3.2))
        }
        context.fill(dots, with: .color(.accentColor.opacity(0.75)))

        // The station playing now is drawn last and larger, with a ring, so it
        // is findable in a field of three thousand identical dots.
        if !current.isEmpty,
           let station = model.stations.first(where: { $0.uuid == current })
            ?? (model.status.station.lat != nil ? model.status.station : nil),
           let lon = station.lon, let lat = station.lat,
           let at = globe.project(lon, lat) {
            context.fill(Path(ellipseIn: CGRect(x: at.x - 4, y: at.y - 4, width: 8, height: 8)),
                         with: .color(.accentColor))
            context.stroke(Path(ellipseIn: CGRect(x: at.x - 8, y: at.y - 8,
                                                  width: 16, height: 16)),
                           with: .color(.accentColor.opacity(0.6)), lineWidth: 1.4)
        }

        if let hovered = model.hovered, let lon = hovered.lon, let lat = hovered.lat,
           let at = globe.project(lon, lat) {
            context.stroke(Path(ellipseIn: CGRect(x: at.x - 5, y: at.y - 5,
                                                  width: 10, height: 10)),
                           with: .color(.primary), lineWidth: 1.2)
            let label = Text(hovered.name).font(.system(size: 11, weight: .medium))
            context.draw(label, at: CGPoint(x: at.x, y: at.y - 14), anchor: .bottom)
            let where_ = Text(hovered.country).font(.system(size: 9))
                .foregroundStyle(.secondary)
            context.draw(where_, at: CGPoint(x: at.x, y: at.y - 2), anchor: .bottom)
        }
    }
}

private extension Double {
    /// Inclusive-ish stride helper, only so the graticule reads as one line.
    func stride(to end: Double, by step: Double) -> [Double] {
        Swift.stride(from: self, through: end, by: step).map { $0 }
    }
}

// MARK: - the panel

struct ContentView: View {
    @ObservedObject var model: Model
    @FocusState var searching: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                GlobeView(model: model)
                    .frame(width: Layout.globeWidth, height: Layout.globeHeight)
                Divider()
                sidebar.frame(width: Layout.sidebarWidth)
            }
            Divider()
            nowPlaying
            Divider()
            hints
        }
        .frame(width: Layout.panelWidth, height: Layout.panelHeight)
        // The key monitor has to stand aside while the field has focus, or
        // typing "random" tunes six stations instead of searching for one.
        .onChange(of: searching) { searchHasFocus = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            searching = true
        }
    }

    // MARK: sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
                TextField("station, genre, city", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searching)
                    .onSubmit { model.showSearch(); searching = false }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            HStack(spacing: 4) {
                tab("Favourites", .favorites) { model.showFavorites() }
                tab("Recent", .recent) { model.showRecent() }
                if model.source == .search {
                    tab("Results", .search) {}
                }
                if model.source == .country {
                    tab(model.countryName.isEmpty ? "Country" : model.countryName,
                        .country) {}
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if model.list.isEmpty {
                VStack(spacing: 6) {
                    Text(emptyText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { scroll in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(model.list.enumerated()), id: \.element.id) { i, s in
                                row(i, s).id(i)
                            }
                        }
                    }
                    .onChange(of: model.selection) { scroll.scrollTo($0, anchor: .center) }
                }
            }
        }
    }

    private var emptyText: String {
        switch model.source {
        case .favorites:
            return "No favourites yet.\nPress f while something is playing."
        case .recent: return "Nothing played yet."
        case .search: return "Nothing found."
        case .country: return "No stations listed there."
        }
    }

    private func tab(_ label: String, _ which: Source, _ action: @escaping () -> Void)
    -> some View {
        let active = model.source == which
        return Text(label)
            .font(.system(size: 11, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(active ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                               : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    private func row(_ index: Int, _ station: Station) -> some View {
        let selected = index == model.selection
        let current = station.uuid == model.status.station.uuid
        return HStack(spacing: 8) {
            Image(systemName: current ? "dot.radiowaves.left.and.right" : "circle.fill")
                .font(.system(size: current ? 10 : 4))
                .foregroundStyle(current ? Color.accentColor : Color.secondary.opacity(0.4))
                .frame(width: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(station.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(station.country.isEmpty ? station.cc : station.country)
                    if station.bitrate > 0 { Text("\(station.bitrate)k") }
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }
            Spacer(minLength: 4)
            if station.lat != nil {
                // Only offered when there is somewhere to spin to: most
                // stations in the directory have no coordinates at all.
                Image(systemName: "globe")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(selected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                             : .clear)
        .contentShape(Rectangle())
        .onTapGesture {
            model.selection = index
            model.play(station)
            model.spin(to: station)
        }
    }

    // MARK: now playing

    private var nowPlaying: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(model.status.playing ? Color.accentColor : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                if model.status.mpv.isEmpty {
                    Text("mpv is not installed, so nothing can play")
                        .font(.system(size: 12))
                    Text("brew install mpv")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else if let note = model.note {
                    Text(note).font(.system(size: 12)).foregroundStyle(.secondary)
                } else if model.status.station.isEmpty {
                    Text(model.partial ? "Filling in the world..." : "Nothing playing")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        Text(model.status.station.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        if model.status.favorite {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(.pink)
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)

            Image(systemName: model.status.muted ? "speaker.slash" : "speaker.wave.2")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text("\(model.status.volume)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 22, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var icon: String {
        if model.status.mpv.isEmpty { return "exclamationmark.triangle" }
        if model.status.buffering { return "clock" }
        if model.status.playing { return "dot.radiowaves.left.and.right" }
        if model.status.paused { return "pause.circle" }
        return "radio"
    }

    private var subtitle: String {
        let where_ = model.status.station.country
        if model.status.buffering { return where_.isEmpty ? "Buffering..." : "\(where_) - buffering..." }
        if !model.status.title.isEmpty {
            return where_.isEmpty ? model.status.title : "\(where_) - \(model.status.title)"
        }
        return where_
    }

    private var hints: some View {
        HStack(spacing: 13) {
            hint("drag", "spin")
            hint("- =", "zoom")
            hint("0", "whole world")
            hint("/", "search")
            hint("space", "play")
            hint("r", "random")
            hint("f", "♥")
            hint("↑↓", "list")
            hint("⏎", "tune")
            hint("[ ]", "volume")
            hint("esc", "close")
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }

    private func hint(_ key: String, _ what: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(what).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
}

/// Whether the search field currently has focus. A global rather than model
/// state because the reader is the AppKit key monitor, which is outside
/// SwiftUI entirely and cannot observe a @Published.
var searchHasFocus = false

// MARK: - window

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let model = Model()

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.regular)

        let host = NSHostingView(rootView: ContentView(model: model))
        host.layout()
        window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                          styleMask: [.titled, .closable],
                          backing: .buffered, defer: false)
        window.title = "Hyperspace Radio"
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.level = .floating

        if let screen = NSScreen.main {
            let area = screen.visibleFrame
            let size = window.frame.size
            window.setFrameOrigin(NSPoint(x: area.midX - size.width / 2,
                                          y: area.midY - size.height / 2))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let model = self.model

        // Zoom. SwiftUI has no scroll-wheel gesture on macOS and a plain
        // NSView behind the Canvas never sees the event either: an unhandled
        // scroll goes UP the responder chain to the superview, not sideways to
        // a sibling. A window-level monitor does see it, and checking where
        // the pointer is keeps the wheel working normally over the station
        // list - the sidebar has to stay scrollable.
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard self?.overGlobe(event) == true else { return event }
            // A trackpad reports many small fractional deltas and a wheel
            // reports whole notches, through the same field. Dividing the
            // precise ones by 16 makes one firm two-finger swipe cover about
            // the same ground as a dozen notches, so both gestures feel like
            // the same control rather than two differently geared ones.
            let delta = Double(event.scrollingDeltaY)
            model.zoom(steps: event.hasPreciseScrollingDeltas ? delta / 16 : delta)
            return nil
        }

        // Pinch. On a trackpad this is the gesture people reach for first, and
        // it arrives as its own event type that a scroll monitor never sees.
        NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard self?.overGlobe(event) == true else { return event }
            model.zoom(steps: Double(event.magnification) * 6)
            return nil
        }

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // esc closes, and it does so even from inside the search field -
            // it is the one key that has to mean the same thing everywhere.
            if event.keyCode == 53 {
                if searchHasFocus {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    return nil
                }
                NSApp.terminate(nil)
                return nil
            }
            // While typing a search, every other key belongs to the field.
            if searchHasFocus { return event }

            switch event.keyCode {
            case 126: model.move(-1); return nil                    // up
            case 125: model.move(1); return nil                     // down
            case 36:                                                // return
                if let station = model.selected {
                    model.play(station)
                    model.spin(to: station)
                }
                return nil
            case 49: model.toggle(); return nil                     // space
            default: break
            }
            guard !event.modifierFlags.contains(.command),
                  let key = event.charactersIgnoringModifiers else { return event }
            switch key {
            case "k": model.move(-1)
            case "j": model.move(1)
            case "r": model.random()
            case "f": model.favorite()
            case "m": model.mute()
            case "s": model.stop()
            // The same keys hyperspace already uses for these two things:
            // Super+Minus / Super+Equal shrink and grow a window, and the
            // volume plugin owns Super+[ and Super+]. Reusing them here means
            // one thing to remember rather than a second private mapping.
            case "-", "_": model.zoom(times: 1 / 1.6)
            case "=", "+": model.zoom(times: 1.6)
            case "0": model.resetGlobe()
            case "[": model.volume(-5)
            case "]": model.volume(5)
            case "g": if let station = model.selected { model.spin(to: station) }
            case "/":
                // Handled here rather than as a TextField shortcut so it works
                // wherever focus happens to be when the panel opens.
                NotificationCenter.default.post(name: .focusSearch, object: nil)
            default: return event
            }
            return nil
        }
    }

    /// Whether a pointer event happened over the globe rather than over the
    /// station list, which has to keep scrolling normally.
    private func overGlobe(_ event: NSEvent) -> Bool {
        guard let content = window?.contentView else { return false }
        let local = content.convert(event.locationInWindow, from: nil)
        // NSHostingView is flipped, but not every AppKit view is, and this has
        // to agree with SwiftUI's .global space either way.
        let point = content.isFlipped
            ? local
            : CGPoint(x: local.x, y: content.bounds.height - local.y)
        return Layout.globeRect.contains(point)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

extension Notification.Name {
    static let focusSearch = Notification.Name("hyperspace.radio.focusSearch")
}

@main
enum Main {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
