import AppKit
import SwiftUI
import Testing
@testable import SplarkKit
@testable import SplarkUI

@MainActor @Suite struct SettingsViewTests {
    @Test func everySettingsStateRendersInBothSchemes() throws {
        let states = SettingsGallery.states()
        #expect(states.count == 10)
        for (name, view) in states {
            for scheme in [ColorScheme.light, .dark] {
                let png = try #require(Snapshot.png(view, scheme: scheme, scale: 1), "\(name)")
                let rep = try #require(NSBitmapImageRep(data: png))
                #expect(rep.pixelsWide == 520 && rep.pixelsHigh >= 200, "\(name)")
            }
        }
    }

    @Test func theSettingsWindowHasATransparentTitleBar() {
        let model = SettingsModel(services: PreviewSettingsServices())
        let controller = SettingsWindowController(model: model)
        #expect(controller.window.title == "Splark Settings" && controller.window.titlebarAppearsTransparent)
        #expect(!controller.isVisible && model.section == .workspaces)
    }

    /// A shown window resizes to each section, keeping its top edge. (Sized by its hosting controller, it looped and crashed on macOS 26.)
    @Test func theShownWindowFollowsEachSectionsHeight() async throws {
        _ = NSApplication.shared
        let model = SettingsModel(services: PreviewSettingsServices(), now: { now })
        let controller = SettingsWindowController(model: model)
        controller.show()
        #expect(await eventually { controller.window.frame.height > 300 })   // Workspaces, with four rows
        let top = controller.window.frame.maxY
        var height = controller.window.frame.height
        for section in [SettingsModel.Section.about, .general, .workspaces] {
            model.section = section
            #expect(await eventually { abs(controller.window.frame.height - height) > 1 }, "\(section)")
            #expect(abs(controller.window.frame.maxY - top) < 1, "\(section)")
            height = controller.window.frame.height
        }
        controller.close()
    }
}
