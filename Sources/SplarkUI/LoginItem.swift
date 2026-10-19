import ServiceManagement

/// Open at login (spec §4.4, §4.5).
@MainActor public protocol LoginItemControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ on: Bool) throws
}

/// The app itself as a login item, through `SMAppService` (macOS 13+). macOS may tell the user it was added.
@MainActor public final class MainAppLoginItem: LoginItemControlling {
    public init() {}

    public var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    public func setEnabled(_ on: Bool) throws {
        guard on != isEnabled else { return }
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
