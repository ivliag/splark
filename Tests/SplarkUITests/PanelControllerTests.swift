import AppKit
import SwiftUI
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

    /// The spark's frame doesn't stay put while the panel is open: with a second display it can follow the active menu
    /// bar, and other menu-bar items push it along. Opening or closing "Just comments" resizes the panel, which then
    /// jumped off the top of an external display. It keeps the spot it opened at until it closes.
    @Test func resizingWhileOpenKeepsTheSpotItOpenedAt() {
        let external = NSRect(x: -191, y: 982, width: 1920, height: 1050)    // visible frame of a display above the laptop
        var spark = NSRect(x: 1000, y: 2036, width: 45, height: 22)
        let controller = PanelController(anchor: { spark }, screen: { external })
        controller.contentSizeChanged(CGSize(width: 372, height: 300))
        controller.show()
        let opened = controller.window.frame
        spark = NSRect(x: 889, y: 2600, width: 45, height: 22)
        controller.contentSizeChanged(CGSize(width: 372, height: 420))
        #expect(controller.window.frame == NSRect(x: opened.minX, y: opened.maxY - 420, width: 372, height: 420))
        controller.close()
        controller.show()
        let reopened = PanelController.frame(for: CGSize(width: 372, height: 420), under: spark, in: external)
        #expect(controller.window.frame.maxY == reopened.maxY)   // the next opening goes under the spark wherever it is now
        controller.close()
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

    /// The content fills the panel, on glass (macOS 26) and on the frosted material alike. On glass it was left at its
    /// own size, so a short panel showed its content shifted and cut off.
    @Test func theContentFillsThePanel() throws {
        let controller = PanelController(anchor: { nil }, screen: { NSRect(x: 0, y: 0, width: 1512, height: 944) })
        controller.setContent(Color.clear.frame(width: 372, height: 140))
        controller.contentSizeChanged(CGSize(width: 372, height: 140))
        let background = try #require(controller.window.contentView)
        background.layoutSubtreeIfNeeded()
        let hosting = try #require(Self.hostingView(in: background))
        #expect(hosting.convert(hosting.bounds, to: background) == background.bounds)
        #expect(background.bounds.size == CGSize(width: 372, height: 140))
    }

    /// On macOS 26 the glass's own layout resized the window's content view apart from the window (twice its size on
    /// Retina), centring the panel's content off the panel. The content view keeps the window's size whatever asks.
    @Test func theContentViewKeepsTheWindowsSize() throws {
        let controller = PanelController(anchor: { nil }, screen: { NSRect(x: 0, y: 0, width: 1512, height: 944) })
        controller.setContent(Color.clear.frame(width: 372, height: 140))
        controller.contentSizeChanged(CGSize(width: 372, height: 140))
        let background = try #require(controller.window.contentView)
        background.setFrameSize(NSSize(width: 744, height: 280))
        #expect(background.frame.size == controller.window.frame.size)
    }

    /// With a second display the spark can follow the active menu bar while the panel is open. A resize then ("Just
    /// comments" opening) must keep the panel where it opened, not jump to the other screen's menu bar.
    @Test func whileOpenItStaysWhereItOpened() {
        _ = NSApplication.shared
        let laptop = NSRect(x: 0, y: 0, width: 1512, height: 944)
        let external = NSRect(x: 0, y: 982, width: 1920, height: 1050)
        var spark = NSRect(x: 1200, y: 945, width: 40, height: 24)
        var screen = laptop
        let controller = PanelController(anchor: { spark }, screen: { screen })
        controller.contentSizeChanged(CGSize(width: 372, height: 300))
        controller.show()
        defer { controller.close() }
        let opened = controller.window.frame
        spark = NSRect(x: 1000, y: 2036, width: 40, height: 22)
        screen = external
        controller.contentSizeChanged(CGSize(width: 372, height: 420))
        #expect(controller.window.frame.maxY == opened.maxY && controller.window.frame.midX == opened.midX)
        #expect(controller.window.frame.height == 420)
    }

    static func hostingView(in view: NSView) -> NSView? {
        if String(describing: type(of: view)).hasPrefix("NSHostingView") { return view }
        return view.subviews.lazy.compactMap { hostingView(in: $0) }.first
    }
}
