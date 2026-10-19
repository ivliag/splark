import AppKit
import SwiftUI

/// Renders a SwiftUI view offscreen to PNG: for tests, `splark-dev render-ui` and the PR's screenshots.
@MainActor public enum Snapshot {
    public static func png<V: View>(_ view: V, scheme: ColorScheme, scale: CGFloat = 2) -> Data? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
        renderer.scale = scale
        guard let image = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
