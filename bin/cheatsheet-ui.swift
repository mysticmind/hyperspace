// Native keybinding cheatsheet, on Super+K. Built on first run by
// bin/cheatsheet-toggle.
//
// It parses nothing: `bin/cheatsheet --json` is still the single source of
// truth for what the bindings are, read straight from the live aerospace.toml,
// so the sheet cannot drift from the keys it documents.
//
// The reason this exists rather than the Alacritty version (kept as
// bin/cheatsheet-term for machines with no swiftc): a terminal window cannot be
// asked how big it will be, so that path had to predict its own size from the
// glyph metrics of a particular font at a particular size, then do arithmetic
// to centre it - constants that go silently wrong when the font changes, and
// which put the window off screen when they drift far enough. A native window
// measures itself. Centring is then a fact rather than a guess.
//
// Colours are all semantic - Color.primary, .secondary and the window's own
// background - so light and dark mode both come out right with no palette of
// our own to maintain.
import AppKit
import SwiftUI

struct Row: Codable {
    let key: String
    let desc: String
}

struct Section: Codable {
    let label: String
    let rows: [Row]
}

// A flattened cheatsheet entry. Headers and bindings share one list so the
// column splitter can balance on rendered height rather than on sections,
// which are wildly uneven - `main` dwarfs the two mode sections.
enum Item {
    case header(String)
    case binding(Row)
}

let cheatsheetCmd = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""

func loadSections() -> [Section] {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: cheatsheetCmd)
    p.arguments = ["--json"]
    let o = Pipe()
    p.standardOutput = o
    p.standardError = Pipe()
    do { try p.run() } catch { return [] }
    let d = o.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (try? JSONDecoder().decode([Section].self, from: d)) ?? []
}

func flatten(_ sections: [Section]) -> [Item] {
    var items: [Item] = []
    for s in sections {
        items.append(.header(s.label))
        items.append(contentsOf: s.rows.map { Item.binding($0) })
    }
    return items
}

// Equal-height columns, never breaking directly after a header - a header
// stranded at the foot of a column labels nothing.
func split(_ items: [Item], into columns: Int) -> [[Item]] {
    guard columns > 1, !items.isEmpty else { return [items] }
    let height = Int((Double(items.count) / Double(columns)).rounded(.up))
    var out: [[Item]] = []
    var start = 0
    for c in 0..<columns {
        guard start < items.count else { out.append([]); continue }
        var end = (c == columns - 1) ? items.count : min(start + height, items.count)
        if c < columns - 1, end - 1 >= start, case .header = items[end - 1] { end -= 1 }
        out.append(Array(items[start..<end]))
        start = end
    }
    return out
}

struct ContentView: View {
    let columns: [[Item]]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Keybindings").font(.system(size: 15, weight: .semibold))
                Text("Super = Caps Lock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Super+K")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            HStack(alignment: .top, spacing: 26) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, col in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(col.enumerated()), id: \.offset) { _, item in
                            switch item {
                            case .header(let label): header(label)
                            case .binding(let row): binding(row)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            Text("Super+K or Esc closes this")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
        }
    }

    private func header(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .foregroundStyle(.tertiary)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func binding(_ row: Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(row.key)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 132, alignment: .leading)
            Text(row.desc)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

// AppKit drives the window rather than SwiftUI's App lifecycle: this binary has
// no .app bundle - that is the point, there is nothing to install - and without
// one a `Window` scene never actually appears.
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.regular)

        let sections = loadSections()
        let host = NSHostingView(rootView: ContentView(columns: split(flatten(sections), into: 2)))
        host.layout()

        // fittingSize is the whole point of the rewrite: the view reports what
        // it needs and the window takes that, instead of a script guessing from
        // font metrics. Clamped so an enormous config cannot exceed the screen.
        var size = host.fittingSize
        if let vf = NSScreen.main?.visibleFrame {
            size.width = min(size.width, vf.width - 80)
            size.height = min(size.height, vf.height - 80)
        }

        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable],
                          backing: .buffered,
                          defer: false)
        window.title = "hyperspace-cheatsheet"
        window.contentView = host
        window.isReleasedWhenClosed = false
        // Summoned by a chord over whatever you are working in, so it has to
        // sit above that window rather than behind it.
        window.level = .floating

        // NSWindow.center() is not a true centre - AppKit places the window
        // about a third of the way down. visibleFrame so it never lands under
        // the Dock, and it already accounts for the menu bar either way.
        //
        // Centre on the WINDOW frame, not the content size used above: a
        // titled window is its content plus a title bar, so centring by the
        // content height sits the window a half-title-bar too high.
        if let vf = NSScreen.main?.visibleFrame {
            let outer = window.frame.size
            window.setFrameOrigin(NSPoint(x: vf.midX - outer.width / 2,
                                          y: vf.midY - outer.height / 2))
        } else {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { NSApp.terminate(nil); return nil }   // esc
            return e
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
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
