import AppKit
import Testing
@testable import SplarkUI

@MainActor @Suite struct PanelControllerTests {
    let screen = NSRect(x: 0, y: 0, width: 1512, height: 944)          // visible frame, below a 38 pt menu bar
    let spark = NSRect(x: 1200, y: 945, width: 40, height: 24)          // the status item, in the menu bar

    @Test func sitsCentredUnderTheSparkWithAGap() {
        let frame = PanelController.frame(for: CGSize(width: 372, height: 400), under: spark, in: screen)
        #expect(frame == NSRect(x: 1220 - 186, y: 945 - 6 - 400, width: 372, height: 400))
    }

    @Test func staysOnScreenNearTheRightEdge() {
        let frame = PanelController.frame(for: CGSize(width: 372, height: 300), under: NSRect(x: 1480, y: 945, width: 30, height: 24), in: screen)
        #expect(frame.maxX == screen.maxX - 8)
    }

    @Test func neverTallerThanSeventyPercentOfTheScreen() {
        let frame = PanelController.frame(for: CGSize(width: 372, height: 2000), under: spark, in: screen)
        #expect(frame.height == (944 * 0.7).rounded(.down))
        #expect(PanelController.maxContentHeight(in: screen) == (944 * 0.7).rounded(.down))
    }

    @Test func withoutTheSparkItSitsTopRight() {
        let frame = PanelController.frame(for: CGSize(width: 372, height: 300), under: nil, in: screen)
        #expect(frame.maxX == screen.maxX - 8 && frame.maxY == screen.maxY - 6)
    }

    @Test func thePanelIsNonActivatingAndCanTakeTheKeyboard() {
        let controller = PanelController(anchor: { nil }, screen: { NSRect(x: 0, y: 0, width: 1000, height: 800) })
        let panel = controller.window
        #expect(panel.styleMask.contains(.nonactivatingPanel) && panel.styleMask.contains(.borderless))
        #expect(panel.canBecomeKey && !panel.canBecomeMain && !panel.isOpaque && panel.hasShadow)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces) && panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(!controller.isShown)
    }

    @Test func followsItsContentsHeightKeepingTheTopEdge() {
        let controller = PanelController(anchor: { NSRect(x: 500, y: 760, width: 40, height: 24) }, screen: { NSRect(x: 0, y: 0, width: 1000, height: 760) })
        controller.contentSizeChanged(CGSize(width: 372, height: 300))
        let top = controller.window.frame.maxY
        controller.contentSizeChanged(CGSize(width: 372, height: 420))
        #expect(controller.window.frame.height == 420 && controller.window.frame.maxY == top)
    }

    @Test func escapeIsForwarded() {
        var escaped = false
        let controller = PanelController(anchor: { nil }, screen: { .zero })
        controller.onEscape = { escaped = true }
        controller.window.cancelOperation(nil)
        #expect(escaped)
    }

    /// A laptop with an external display to its right, each with its own menu bar: the panel opens on the spark's screen.
    @Test func opensOnTheScreenTheSparkIsOn() {
        let laptop = (frame: NSRect(x: 0, y: 0, width: 1512, height: 982), visible: NSRect(x: 0, y: 0, width: 1512, height: 944))
        let external = (frame: NSRect(x: 1512, y: 0, width: 2560, height: 1440), visible: NSRect(x: 1512, y: 0, width: 2560, height: 1415))
        let sparkOnExternal = NSRect(x: 3900, y: 1416, width: 40, height: 24)
        #expect(PanelController.visibleFrame(containing: sparkOnExternal, in: [laptop, external]) == external.visible)
        #expect(PanelController.visibleFrame(containing: spark, in: [laptop, external]) == laptop.visible)
        #expect(PanelController.visibleFrame(containing: nil, in: [laptop, external]) == laptop.visible)
    }

    /// Undocking moves Splark to a smaller screen: the content's height limit follows at the next opening.
    @Test func theHeightLimitFollowsTheScreenAtEachOpening() {
        var visible = NSRect(x: 0, y: 0, width: 2560, height: 1415)
        let controller = PanelController(anchor: { nil }, screen: { visible })
        controller.show()
        #expect(controller.layout.maxHeight == (1415 * 0.7).rounded(.down))
        controller.close()
        visible = NSRect(x: 0, y: 0, width: 1512, height: 944)
        controller.show()
        #expect(controller.layout.maxHeight == (944 * 0.7).rounded(.down))
        controller.close()
    }
}
