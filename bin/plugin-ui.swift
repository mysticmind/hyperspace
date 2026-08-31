// Native plugin panel, on Super+Shift+K. Built on first run by bin/plugin-ui.
//
// This owns no state and parses no TOML: it shells out to bin/plugin for
// everything - `list --json` to read, `enable`/`disable` to write - so a
// toggle here runs the same hooks, config rebuild and rollback-on-collision
// as the command line, and there is one source of truth for what a plugin is.
//
// Keyboard first. The panel is opened by a chord, so a window that then needs
// the mouse to flip one switch defeats the point: j/k or the arrows move, space
// toggles, 1-9 jump straight to a row, esc closes. The switches still work for
// a pointer - they are simply not the path this is built around.
import AppKit
import SwiftUI

struct Plugin: Codable, Identifiable {
    let name: String
    let description: String
    let enabled: Bool
    var id: String { name }
}

// bin/plugin's path, handed over by the wrapper, because this binary lives in
// a cache directory and cannot find the repo by its own location.
let pluginCmd = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ""

func run(_ args: [String]) -> (code: Int32, out: String, err: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: pluginCmd)
    p.arguments = args
    let o = Pipe(), e = Pipe()
    p.standardOutput = o
    p.standardError = e
    do { try p.run() } catch { return (1, "", "\(error)") }
    let od = o.fileHandleForReading.readDataToEndOfFile()
    let ed = e.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus,
            String(decoding: od, as: UTF8.self),
            String(decoding: ed, as: UTF8.self))
}

func load() -> [Plugin] {
    let r = run(["list", "--json"])
    guard let d = r.out.data(using: .utf8),
          let list = try? JSONDecoder().decode([Plugin].self, from: d)
    else { return [] }
    return list
}

// Keys arrive through an AppKit monitor rather than SwiftUI's focus system:
// this binary has no .app bundle, and without one the window never reliably
// becomes first responder for .onKeyPress. A reference type is what lets the
// monitor's closure mutate the same state the view is rendering.
final class Model: ObservableObject {
    @Published var plugins: [Plugin] = load()
    @Published var selection: Int = 0
    @Published var busy: Set<String> = []
    @Published var failure: String?

    func move(_ delta: Int) {
        guard !plugins.isEmpty else { return }
        selection = min(max(selection + delta, 0), plugins.count - 1)
    }

    func jump(to index: Int) {
        guard plugins.indices.contains(index) else { return }
        selection = index
        toggle(plugins[index])
    }

    func toggleSelected() {
        guard plugins.indices.contains(selection) else { return }
        toggle(plugins[selection])
    }

    func toggle(_ p: Plugin) {
        // A second press while the rebuild is still running would race the
        // reload and report the pre-toggle state as the outcome.
        guard !busy.contains(p.name) else { return }
        busy.insert(p.name)
        failure = nil
        let action = p.enabled ? "disable" : "enable"
        DispatchQueue.global().async {
            // --yes: a GUI toggle has no stdin to answer a prompt with.
            let r = run([action, p.name, "--yes"])
            // Re-read rather than assume: bin/plugin rolls back on a binding
            // collision, so the truth after a toggle is whatever it now says.
            let fresh = load()
            DispatchQueue.main.async {
                self.busy.remove(p.name)
                self.plugins = fresh
                self.selection = min(self.selection, max(0, fresh.count - 1))
                if r.code != 0 {
                    self.failure = (r.out + r.err)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Plugins").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("Super+Shift+K")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ForEach(Array(model.plugins.enumerated()), id: \.element.id) { i, p in
                row(i, p)
                if i != model.plugins.count - 1 {
                    Divider().padding(.leading, 18)
                }
            }

            if let failure = model.failure {
                Divider()
                Text(failure)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            keyHints
        }
        .frame(width: 470)
    }

    private var keyHints: some View {
        HStack(spacing: 14) {
            hint("j / k", "move")
            hint("space", "toggle")
            hint("1-9", "jump")
            hint("esc", "close")
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private func hint(_ key: String, _ what: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(what)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private func row(_ i: Int, _ p: Plugin) -> some View {
        let selected = i == model.selection
        return HStack(spacing: 14) {
            // The number is the shortcut, not decoration - it is what 1-9 acts
            // on, so it has to be visible to be usable.
            Text("\(i + 1)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(selected ? .primary : .tertiary)
                .frame(width: 12, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(p.name).font(.system(size: 13, weight: .medium))
                Text(p.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            // A rebuild plus an AeroSpace reload is not instant, and a switch
            // that springs back looks broken - so the row shows it is working.
            if model.busy.contains(p.name) {
                ProgressView().controlSize(.small)
            } else {
                Toggle("", isOn: Binding(get: { p.enabled },
                                         set: { _ in model.toggle(p) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        // The unemphasised selection colour rather than a tinted accent: it
        // is defined against the list background in both appearances, so the
        // row reads in dark mode without restyling every label inside it the
        // way a filled accent row would demand.
        .background(selected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                             : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { model.selection = i }
    }
}

// AppKit drives the window rather than SwiftUI's App lifecycle. This binary
// has no .app bundle - that is the point, there is nothing to install - and
// without one a `Window` scene never actually appears: the process runs
// happily with no window at all. Creating the NSWindow by hand and hosting
// the SwiftUI view in it works with no bundle, no Info.plist and no signing.
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let model = Model()

    func applicationDidFinishLaunching(_ note: Notification) {
        // Without .regular the panel launches behind everything, which for a
        // keyboard-triggered window reads as "nothing happened".
        NSApp.setActivationPolicy(.regular)

        let host = NSHostingView(rootView: ContentView(model: model))
        host.layout()
        window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                          styleMask: [.titled, .closable],
                          backing: .buffered,
                          defer: false)
        window.title = "Hyperspace Plugins"
        window.contentView = host
        window.isReleasedWhenClosed = false
        // Above ordinary windows, not just above this app's own. It is summoned
        // by a chord over whatever you are working in, so it has to sit on top
        // of that - a panel that slips behind the window you called it from
        // reads as not having opened at all.
        window.level = .floating

        // NSWindow.center() is not a true centre - AppKit puts the window
        // roughly a third of the way down, which reads as "too high" next to
        // the cheatsheet. Centre on visibleFrame by hand: visibleFrame rather
        // than frame so the panel never sits under the Dock, and it already
        // accounts for the menu bar whether or not it is auto-hidden.
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
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            switch e.keyCode {
            case 53: NSApp.terminate(nil); return nil          // esc
            case 126: model.move(-1); return nil               // up
            case 125: model.move(1); return nil                // down
            case 49, 36: model.toggleSelected(); return nil    // space, return
            default: break
            }
            // Let ⌘-anything through: ⌘W and ⌘Q still have to close the panel.
            guard !e.modifierFlags.contains(.command),
                  let c = e.charactersIgnoringModifiers else { return e }
            if let n = Int(c), (1...9).contains(n) {
                model.jump(to: n - 1)
                return nil
            }
            switch c {
            case "k": model.move(-1); return nil
            case "j": model.move(1); return nil
            default: return e
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

@main
enum Main {
    // Held here so the delegate is not deallocated the moment main() returns
    // into the run loop.
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
