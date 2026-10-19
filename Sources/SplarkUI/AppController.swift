import AppKit
import SplarkKit
import SwiftUI

/// Runs Splark (spec §5.2): the engine, the spark in the menu bar, the panel under it, setup on first run, and Settings.
@MainActor public final class AppController {
    public let engine: SplarkEngine
    private(set) var statusItem: StatusItemController!
    private(set) var panel: PanelController!
    private(set) var panelModel: PanelModel!
    private(set) var setup: SetupWindowController?
    private(set) var setupModel: SetupModel?
    private(set) var settings: SettingsWindowController?
    private(set) var settingsModel: SettingsModel?
    private let loginItem: LoginItemControlling
    private var watches: [Watch] = []

    public convenience init(environment: EngineEnvironment = .live(), loginItem: LoginItemControlling = MainAppLoginItem()) {
        self.init(environment: environment, loginItem: loginItem, statusButton: nil)
    }

    /// `statusButton` stands in for the menu bar's in tests.
    init(environment: EngineEnvironment, loginItem: LoginItemControlling, statusButton: NSButton?) {
        engine = SplarkEngine(environment: environment)
        self.loginItem = loginItem
        let handlers = StatusItemController.Handlers(
            toggle: { [weak self] in self?.togglePanel() },
            refresh: { [weak self] in Task { await self?.engine.refreshNow() } },
            settings: { [weak self] in self?.showSettings() },
            pauseSummaries: { [weak self] in self?.setSummariesPaused($0) },
            quit: { NSApp.terminate(nil) })
        statusItem = statusButton.map { StatusItemController(button: $0, handlers: handlers) } ?? StatusItemController(handlers: handlers)
        panel = PanelController(anchor: { [weak self] in self?.statusItem.buttonFrameOnScreen })
        panelModel = PanelModel(actions: engine.actions, muting: engine, close: { [weak self] in self?.panel.close() },
                                openSlack: { NSWorkspace.shared.open(URL(string: "slack://open")!) },
                                openSettings: { [weak self] in self?.showSettings() })
        panel.onEscape = { [weak self] in self?.panelModel.escape() }
        panel.onClose = { [weak self] in self?.panelModel.panelClosed() }
    }

    /// Starts syncing, puts the spark in the menu bar, and opens setup when nothing is connected yet.
    public func launch() {
        engine.start()
        panel.setContent(LivePanel(engine: engine, model: panelModel, layout: panel.layout) { [weak self] in
            self?.panel.contentSizeChanged($0)
        })
        let engine = engine
        watches = [
            Watch({ (Presenter.statusItem(engine.inbox.summary, showCount: engine.settings.showCount), engine.settings.summariesPaused) }) { [weak self] state in
                self?.statusItem.show(state.0)
                self?.statusItem.setSummariesPaused(state.1)
            },
            Watch({ engine.actions.lastFailure }) { [weak self] failure in
                if let failure { self?.panelModel.showFailure(failure) }
            },
        ]
        if engine.workspaces.isEmpty && engine.pendingApps.isEmpty { showSetup() }
    }

    /// Before quitting: sends pending mark-reads and saves.
    public func terminate() async {
        watches.forEach { $0.cancel() }
        watches = []
        panel.close()
        await engine.stop()
    }

    /// A click on the spark. Until a workspace is connected there's nothing for the panel to show, so the click leads
    /// to what finishes setting up: setup itself, or Settings → Slack when a workspace waits for an admin.
    public func togglePanel() {
        guard engine.workspaces.isEmpty else { return panel.toggle() }
        if engine.pendingApps.isEmpty { showSetup() } else { showSettings(.slack) }
    }

    func setSummariesPaused(_ paused: Bool) { Task { await engine.setSummariesPaused(paused) } }

    // MARK: Windows

    /// First run, or after Reset: all four steps. From Settings' "+ Add workspace": only the Slack step.
    public func showSetup(addingWorkspace: Bool = false) {
        if let setup, setupModel?.addingWorkspace == addingWorkspace { return setup.show() }
        setup?.close()
        let services = LiveSetupServices(engine: engine, loginItem: loginItem, onFinish: { [weak self] in self?.setup?.close() })
        let model = SetupModel(services: services, addingWorkspace: addingWorkspace)
        let window = SetupWindowController(model: model)
        window.onClose = { [weak self, weak window] in
            guard let self, self.setup === window else { return }
            self.setup = nil
            self.setupModel = nil
        }
        setup = window
        setupModel = model
        window.show()
    }

    public func showSettings(_ section: SettingsModel.Section = .general) {
        panel.close()
        if settings == nil {
            let services = LiveSettingsServices(engine: engine, loginItem: loginItem, onAddWorkspace: { [weak self] in self?.showSetup(addingWorkspace: true) })
            let model = SettingsModel(services: services, onReset: { [weak self] in self?.didReset() })
            let window = SettingsWindowController(model: model)
            window.onClose = { [weak self, weak window] in
                guard let self, self.settings === window else { return }
                self.settings = nil
                self.settingsModel = nil
            }
            settings = window
            settingsModel = model
        }
        settings?.show(section)
    }

    /// Reset stopped the engine and forgot everything: start again from setup.
    private func didReset() {
        settings?.close()
        setup?.close()
        engine.start()
        showSetup()
    }

    // MARK: Menus

    /// The app's main menu. It never shows (Splark has no Dock icon or menu bar of its own), but its key equivalents
    /// give the setup and Settings windows ⌘V, ⌘C, ⌘A, ⌘Z and ⌘W. No ⌘Q: the panel takes the keyboard while another
    /// app stays frontmost, so ⌘Q meant for that app would quit Splark. Quit is in the spark's menu.
    public static func mainMenu() -> NSMenu {
        let main = NSMenu()
        func item(_ title: String, _ action: Selector, _ key: String, _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            return item
        }
        func add(_ title: String, _ items: [NSMenuItem]) {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            holder.submenu = menu
            main.addItem(holder)
        }
        add("Splark", [])   // AppKit takes the first menu as the application menu
        add("Edit", [item("Undo", Selector(("undo:")), "z"), item("Redo", Selector(("redo:")), "z", [.command, .shift]), .separator(),
                     item("Cut", #selector(NSText.cut(_:)), "x"), item("Copy", #selector(NSText.copy(_:)), "c"),
                     item("Paste", #selector(NSText.paste(_:)), "v"), item("Select All", #selector(NSText.selectAll(_:)), "a")])
        add("Window", [item("Close", #selector(NSWindow.performClose(_:)), "w")])
        return main
    }

    // MARK: Debugging

    /// Opens the panel whatever is connected: for `SPLARK_DEBUG_PANEL` runs over the fixtures.
    public func showPanelForDebugging() { panel.show() }

    /// Where the spark and the panel are: for `SPLARK_DEBUG_PANEL` runs, checked from a terminal without screen
    /// recording. (Opened without a click, the panel can't take the keyboard, so that isn't reported.)
    public func debugReport() -> String {
        let background = panel.window.contentView
        func hosting(in view: NSView) -> NSView? {
            if String(describing: type(of: view)).hasPrefix("NSHostingView") { return view }
            return view.subviews.lazy.compactMap { hosting(in: $0) }.first
        }
        let contentFrame = background.flatMap { background in hosting(in: background).map { $0.convert($0.bounds, to: background) } }
        return """
        status item: \(statusItem.buttonFrameOnScreen.map { "\($0)" } ?? "no window")
        panel: shown=\(panel.isShown) frame=\(panel.window.frame) max height=\(panel.maxContentHeight)
        content: \(contentFrame.map { "\($0)" } ?? "none") in \(panel.window.contentView.map { "\($0.bounds)" } ?? "none")
        """
    }
}

/// The panel's content in the app: the engine's inbox and header line, with times kept fresh.
struct LivePanel: View {
    let engine: SplarkEngine
    let model: PanelModel
    let layout: PanelLayout   // the height limit, for the screen the panel last opened on
    let onSize: (CGSize) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            PanelView(inbox: engine.inbox,
                      status: Presenter.headerStatus(workspaces: engine.workspaces, sync: engine.syncStatus, triage: engine.triageState, now: context.date),
                      model: model, now: context.date, layout: .live(maxHeight: layout.maxHeight), onSize: onSize)
        }
    }
}
