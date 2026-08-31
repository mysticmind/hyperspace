// Native plugin panel, on Super+Shift+K. Built on first run by bin/plugin-ui.
//
// This owns no state and parses no TOML: it shells out to bin/plugin for
// everything — `list --json` to read, `enable`/`disable` to write — so a
// toggle here runs the same hooks, config rebuild and rollback-on-collision
// as the command line, and there is one source of truth for what a plugin is.
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

struct ContentView: View {
    @State private var plugins: [Plugin] = load()
    @State private var busy: Set<String> = []
    @State private var failure: String?

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

            ForEach(plugins) { p in
                row(p)
                if p.id != plugins.last?.id {
                    Divider().padding(.leading, 18)
                }
            }

            if let failure {
                Divider()
                Text(failure)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 470)
    }

    private func row(_ p: Plugin) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(p.name).font(.system(size: 13, weight: .medium))
                Text(p.description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            // A rebuild plus an AeroSpace reload is not instant, and a switch
            // that springs back looks broken — so the row shows it is working.
            if busy.contains(p.name) {
                ProgressView().controlSize(.small)
            } else {
                Toggle("", isOn: Binding(get: { p.enabled },
                                         set: { _ in toggle(p) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func toggle(_ p: Plugin) {
        busy.insert(p.name)
        failure = nil
        let action = p.enabled ? "disable" : "enable"
        DispatchQueue.global().async {
            let r = run([action, p.name])
            // Re-read rather than assume: bin/plugin rolls back on a binding
            // collision, so the truth after a toggle is whatever it now says.
            let fresh = load()
            DispatchQueue.main.async {
                busy.remove(p.name)
                plugins = fresh
                if r.code != 0 {
                    failure = (r.out + r.err).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
    }
}

// AppKit drives the window rather than SwiftUI's App lifecycle. This binary
// has no .app bundle — that is the point, there is nothing to install — and
// without one a `Window` scene never actually appears: the process runs
// happily with no window at all. Creating the NSWindow by hand and hosting
// the SwiftUI view in it works with no bundle, no Info.plist and no signing.
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ note: Notification) {
        // Without .regular the panel launches behind everything, which for a
        // keyboard-triggered window reads as "nothing happened".
        NSApp.setActivationPolicy(.regular)

        let host = NSHostingView(rootView: ContentView())
        host.layout()
        window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                          styleMask: [.titled, .closable],
                          backing: .buffered,
                          defer: false)
        window.title = "Hyperspace Plugins"
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.center()
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
    // Held here so the delegate is not deallocated the moment main() returns
    // into the run loop.
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
