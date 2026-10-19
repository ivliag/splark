import AppKit
import SplarkKit

/// The menu-bar item (spec §4.2): the spark at the inbox's level, and how many items need you. A left click toggles
/// the panel; a right click, ⌥-click or ⌃-click opens the menu.
@MainActor public final class StatusItemController: NSObject {
    public struct Handlers {
        let toggle: () -> Void
        let refresh: () -> Void
        let settings: () -> Void
        let pauseSummaries: (Bool) -> Void
        let quit: () -> Void

        public init(toggle: @escaping () -> Void, refresh: @escaping () -> Void, settings: @escaping () -> Void,
                    pauseSummaries: @escaping (Bool) -> Void, quit: @escaping () -> Void) {
            self.toggle = toggle
            self.refresh = refresh
            self.settings = settings
            self.pauseSummaries = pauseSummaries
            self.quit = quit
        }
    }

    public enum ClickAction: Equatable { case togglePanel, showMenu }

    private let statusItem: NSStatusItem?
    private let button: NSButton
    private let handlers: Handlers
    private var summariesPaused = false

    /// The real menu-bar item.
    public convenience init(handlers: Handlers) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.init(statusItem: item, button: item.button!, handlers: handlers)
    }

    /// For tests: any button stands in for the menu bar's.
    convenience init(button: NSButton, handlers: Handlers) {
        self.init(statusItem: nil, button: button, handlers: handlers)
    }

    private init(statusItem: NSStatusItem?, button: NSButton, handlers: Handlers) {
        self.statusItem = statusItem
        self.button = button
        self.handlers = handlers
        super.init()
        button.imagePosition = .imageLeft
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// The button's frame on screen, for placing the panel under it.
    public var buttonFrameOnScreen: NSRect? {
        guard let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    public func show(_ content: StatusItemContent) {
        button.image = PixelArt.image(PixelArt.spark, level: content.level, template: true)
        button.title = content.count.map { " \($0)" } ?? ""
        button.setAccessibilityLabel(content.accessibility)
    }

    public func setSummariesPaused(_ paused: Bool) { summariesPaused = paused }

    public static func action(for event: NSEvent?) -> ClickAction {
        guard let event else { return .togglePanel }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.option) || event.modifierFlags.contains(.control) { return .showMenu }
        return .togglePanel
    }

    public func makeMenu(summariesPaused: Bool) -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ key: String, _ action: Selector) -> NSMenuItem {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
            return item
        }
        _ = add("Refresh now", "r", #selector(refresh))
        _ = add("Settings…", ",", #selector(settings))
        add("Pause summaries", "", #selector(togglePause)).state = summariesPaused ? .on : .off
        menu.addItem(.separator())
        _ = add("Quit Splark", "q", #selector(quit))
        return menu
    }

    @objc private func clicked() {
        switch Self.action(for: NSApp.currentEvent) {
        case .togglePanel: handlers.toggle()
        case .showMenu:
            // Attach the menu for this one click, so a left click keeps toggling the panel.
            statusItem?.menu = makeMenu(summariesPaused: summariesPaused)
            button.performClick(nil)
            statusItem?.menu = nil
        }
    }

    @objc private func refresh() { handlers.refresh() }
    @objc private func settings() { handlers.settings() }
    @objc private func togglePause() { handlers.pauseSummaries(!summariesPaused) }
    @objc private func quit() { handlers.quit() }
}
