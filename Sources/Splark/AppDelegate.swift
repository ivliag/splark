import AppKit
import SplarkUI

/// Runs Splark's AppController, and lets it stop the engine before the app quits.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = AppController.mainMenu()
        if ProcessInfo.processInfo.environment["SPLARK_DEBUG_PANEL"] != nil {
            controller = AppController.withoutAccounts()
            controller.launch()
            controller.showFixtures()
            reportPanel()
        } else {
            controller = AppController()
            controller.launch()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await controller.terminate()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Opens the panel over the fixtures, prints where the spark and the panel are, and quits: a check from a
    /// terminal, without screen-recording permission.
    private func reportPanel() {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            controller.togglePanel()
            try? await Task.sleep(for: .seconds(1.5))
            print(controller.debugReport())
            exit(0)
        }
    }
}
