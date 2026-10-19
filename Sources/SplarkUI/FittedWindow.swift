import AppKit
import SwiftUI

/// A window for SwiftUI content with a transparent title bar, whose height follows the content's, keeping its top edge in place.
/// Setup and Settings are both one.
@MainActor public class FittedWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    public var onClose: (() -> Void)?

    init<Content: View>(rootView: Content, size: NSSize, title: String) {
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = title
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        // The content takes its own height, under the title bar, and reports it; the window follows. Letting the hosting
        // controller size the window instead loops on macOS 26, where every resize changes the safe area.
        let hosting = NSHostingController(rootView: rootView
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self] size in self?.resize(to: size) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea())
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.setContentSize(size)
    }

    public var isVisible: Bool { window.isVisible }

    public func show() {
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    public func close() { window.close() }

    public func windowWillClose(_ notification: Notification) { onClose?() }

    private func resize(to size: CGSize) {
        guard size.height > 0 else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        guard abs(frame.height - window.frame.height) > 0.5 || abs(frame.width - window.frame.width) > 0.5 else { return }
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: window.isVisible)
    }
}
