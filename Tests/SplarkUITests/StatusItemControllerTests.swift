import AppKit
import Testing
@testable import SplarkKit
@testable import SplarkUI

@MainActor final class Calls {
    var log: [String] = []
}

@MainActor @Suite struct StatusItemControllerTests {
    let calls = Calls()

    func controller() -> (StatusItemController, NSButton) {
        let button = NSButton()
        let calls = self.calls
        let handlers = StatusItemController.Handlers(
            toggle: { calls.log.append("toggle") }, refresh: { calls.log.append("refresh") }, settings: { calls.log.append("settings") },
            pauseSummaries: { calls.log.append("pause \($0)") }, quit: { calls.log.append("quit") })
        return (StatusItemController(button: button, handlers: handlers), button)
    }

    @Test func showsTheSparkAndHowManyNeedYou() throws {
        let (c, button) = controller()
        c.show(StatusItemContent(level: .bright, count: "3", accessibility: "Splark: 3 need you"))
        let image = try #require(button.image)
        #expect(image.isTemplate && image.size == NSSize(width: 11, height: 11))
        #expect(button.title == " 3")
        #expect(button.accessibilityLabel() == "Splark: 3 need you")
        c.show(StatusItemContent(level: .dimmed, count: nil, accessibility: "Splark: All caught up"))
        #expect(button.title == "")
    }

    @Test func theMenuHasTheSpecsItems() {
        let (c, _) = controller()
        let menu = c.makeMenu(summariesPaused: true)
        #expect(menu.items.map(\.title) == ["Refresh now", "Settings…", "Pause summaries", "", "Quit Splark"])
        #expect(menu.items.map(\.keyEquivalent) == ["r", ",", "", "", "q"])
        #expect(menu.items[2].state == .on)
        #expect(c.makeMenu(summariesPaused: false).items[2].state == .off)
    }

    @Test func menuItemsCallTheirHandlers() {
        let (c, _) = controller()
        let menu = c.makeMenu(summariesPaused: false)
        for i in [0, 1, 2, 4] {   // what a click on the item does (performActionForItem needs a running app)
            let item = menu.items[i]
            _ = (item.target as? NSObject)?.perform(item.action)
        }
        #expect(calls.log == ["refresh", "settings", "pause true", "quit"])
    }

    @Test func rightClickAndOptionClickOpenTheMenuOthersToggleThePanel() {
        func event(_ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        #expect(StatusItemController.action(for: event(.leftMouseUp)) == .togglePanel)
        #expect(StatusItemController.action(for: event(.rightMouseUp)) == .showMenu)
        #expect(StatusItemController.action(for: event(.leftMouseUp, .option)) == .showMenu)
        #expect(StatusItemController.action(for: event(.leftMouseUp, .control)) == .showMenu)
        #expect(StatusItemController.action(for: nil) == .togglePanel)
    }
}
