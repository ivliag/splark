import AppKit
import SwiftUI

extension EnvironmentValues {
    /// True while rendering offscreen: AppKit-backed controls (text fields) draw a look-alike instead.
    @Entry public var isSnapshot = false
}

/// Renders a SwiftUI view offscreen to PNG: for tests, `splark-dev render-ui` and the PR's screenshots.
@MainActor public enum Snapshot {
    public static func png<V: View>(_ view: V, scheme: ColorScheme, scale: CGFloat = 2) -> Data? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme).environment(\.isSnapshot, true))
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
