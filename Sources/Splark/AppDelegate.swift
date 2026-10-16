import AppKit
import SplarkKit

/// Plan 1 shell. Task 3 replaces the title with the pixel spark.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Splark \(SplarkInfo.version)"

        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Splark", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu

        if ProcessInfo.processInfo.environment["SPLARK_DEBUG_STATUS_ITEM"] != nil { reportStatusItem() }
    }

    /// Prints the status item's on-screen frame, so it can be checked from a terminal
    /// without screen-recording permission. Exits after printing.
    private func reportStatusItem() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let window = self?.statusItem.button?.window else { print("status item: no window"); exit(1) }
            print("status item: frame=\(window.frame) visible=\(window.isVisible) onScreen=\(window.occlusionState.contains(.visible))")
            exit(0)
        }
    }
}
