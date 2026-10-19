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
}
