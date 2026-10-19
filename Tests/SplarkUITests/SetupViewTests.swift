import AppKit
import SwiftUI
import Testing
@testable import SplarkKit
@testable import SplarkUI

@MainActor @Suite struct SetupViewTests {
    @Test func everySetupStateRendersInBothSchemes() throws {
        for (name, view) in SetupGallery.states() {
            for scheme in [ColorScheme.light, .dark] {
                let png = try #require(Snapshot.png(view, scheme: scheme, scale: 1), "\(name)")
                let rep = try #require(NSBitmapImageRep(data: png))
                #expect(rep.pixelsWide == 560 && rep.pixelsHigh >= 520, "\(name)")
            }
        }
    }

    @Test func initialsForTiles() {
        #expect(InitialTile.initials("Lumen") == "L")
        #expect(InitialTile.initials("Lumen Community") == "LC")
        #expect(InitialTile.initials("A B C") == "AB")
    }

    @Test func theSetupWindowHasATransparentTitleBar() {
        let controller = SetupWindowController(model: SetupModel(services: PreviewSetupServices()))
        #expect(controller.window.titlebarAppearsTransparent && controller.window.styleMask.contains(.fullSizeContentView))
        #expect(!controller.isVisible)
    }

    @Test func closingTheWindowStopsWaitingForAllow() async {
        let services = FakeSetupServices()
        services.holdUntilCancelled = true
        let model = SetupModel(services: services)
        model.token = "xoxe.xoxp-config"
        let controller = SetupWindowController(model: model)
        let connecting = Task { await model.connect() }
        #expect(await eventually { services.log.last == "authorize 1.2" })
        controller.close()
        await connecting.value
        #expect(services.log.last == "authorize cancelled")
    }

    /// A click on the spark doesn't make Splark the active app, and macOS 14's cooperative activation may not either:
    /// the setup window stayed behind the frontmost app and the click seemed to do nothing (live run). Shown, it's in
    /// front of every app's windows.
    @Test func shownTheWindowIsInFrontOfOtherApps() async throws {
        _ = NSApplication.shared
        let controller = SetupWindowController(model: SetupModel(services: PreviewSetupServices()))
        controller.show()
        defer { controller.close() }
        try await Task.sleep(for: .milliseconds(200))
        // Front to back, only this process's windows (other tests' too) may come before it.
        let windows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
            .filter { ($0[kCGWindowLayer as String] as? Int) == 0 }
        let index = try #require(windows.firstIndex { ($0[kCGWindowNumber as String] as? Int) == controller.window.windowNumber })
        let ahead = windows[..<index].compactMap { $0[kCGWindowOwnerPID as String] as? Int32 }
        #expect(ahead.allSatisfy { $0 == getpid() })
    }
}
