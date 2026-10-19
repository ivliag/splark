import AppKit
import SwiftUI

/// The panel's window: borderless and non-activating (the app you were in stays active), able to take the keyboard for
/// the reply field and Esc. It sits under the menu-bar spark on Liquid Glass (macOS 26) or a frosted material (14–15).
final class SparkPanel: NSPanel {
    var onEscape: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// How tall the panel's content may grow: 70% of the spark's screen, worked out each time the panel opens.
@MainActor @Observable public final class PanelLayout {
    public var maxHeight: CGFloat = 600
}

/// Shows, sizes and dismisses the panel (spec §4.3): 372 pt wide, as tall as its content up to 70% of the screen,
/// closed by a click elsewhere, by Esc, or when another app comes forward.
@MainActor public final class PanelController {
    let window = SparkPanel()
    public private(set) var isShown = false
    public var onEscape: (() -> Void)? {
        get { window.onEscape }
        set { window.onEscape = newValue }
    }
    public var onClose: (() -> Void)?
    public let layout = PanelLayout()

    private let anchor: () -> NSRect?
    private let screen: () -> NSRect
    private var contentSize = CGSize(width: Theme.panelWidth, height: 200)
    private var mouseMonitor: Any?
    private var activationObserver: NSObjectProtocol?

    /// `anchor` gives the spark's frame on screen; `screen` the visible frame to stay inside. By default that is the
    /// screen the spark is on: with "Displays have separate Spaces", every display has its own menu bar and spark.
    public init(anchor: @escaping () -> NSRect?, screen: (() -> NSRect)? = nil) {
        self.anchor = anchor
        self.screen = screen ?? {
            Self.visibleFrame(containing: anchor(), in: NSScreen.screens.map { (frame: $0.frame, visible: $0.visibleFrame) })
        }
    }

    /// The panel's content: a `PanelView` in its `.live` layout, reporting its size to `contentSizeChanged`.
    public func setContent<Content: View>(_ content: Content) {
        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = []
        window.contentView = Self.background(around: hosting)
    }

    public var maxContentHeight: CGFloat { Self.maxContentHeight(in: screen()) }

    public func toggle() { isShown ? close() : show() }

    public func show() {
        guard !isShown else { return }
        isShown = true
        layout.maxHeight = maxContentHeight
        window.setFrame(Self.frame(for: contentSize, under: anchor(), in: screen()), display: false)
        window.orderFrontRegardless()
        window.makeKey()
        // A click in another app, or another app coming forward, closes the panel.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.close() }
            }
    }

    public func close() {
        guard isShown else { return }
        isShown = false
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        mouseMonitor = nil
        activationObserver = nil
        window.orderOut(nil)
        onClose?()
    }

    /// The content's natural size changed: follow it, keeping the top edge under the spark.
    public func contentSizeChanged(_ size: CGSize) {
        contentSize = size
        let frame = Self.frame(for: size, under: anchor(), in: screen())
        window.setFrame(frame, display: isShown)
    }

    // MARK: Geometry

    /// The visible frame of the screen whose frame (menu bar included) holds the spark; the first screen without one.
    static func visibleFrame(containing anchor: NSRect?, in screens: [(frame: NSRect, visible: NSRect)]) -> NSRect {
        let match = anchor.flatMap { anchor in screens.first { $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)) } }
        return (match ?? screens.first)?.visible ?? .zero
    }

    static func maxContentHeight(in screen: NSRect) -> CGFloat { (screen.height * Theme.panelMaxScreenFraction).rounded(.down) }

    /// Centred under the spark, 6 pt below it, inside the screen with an 8 pt margin; top right without a spark.
    static func frame(for size: CGSize, under anchor: NSRect?, in screen: NSRect) -> NSRect {
        let height = min(size.height, maxContentHeight(in: screen))
        let width = size.width
        let top = (anchor?.minY ?? screen.maxY) - 6
        let centredX = anchor.map { $0.midX - width / 2 } ?? screen.maxX - 8 - width
        let x = min(max(centredX, screen.minX + 8), screen.maxX - 8 - width)
        return NSRect(x: x, y: top - height, width: width, height: height)
    }

    // MARK: Background

    private static func background(around content: NSView) -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Theme.panelCorner
            glass.contentView = content
            return glass
        }
        #endif
        let frosted = NSVisualEffectView()
        frosted.material = .popover
        frosted.blendingMode = .behindWindow
        frosted.state = .active
        frosted.wantsLayer = true
        frosted.layer?.cornerRadius = Theme.panelCorner
        frosted.layer?.masksToBounds = true
        content.frame = frosted.bounds
        content.autoresizingMask = [.width, .height]
        frosted.addSubview(content)
        return frosted
    }
}
