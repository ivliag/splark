import AppKit
import SplarkUI
import SwiftUI

/// Renders every UI state with fixture data to PNGs, light and dark, on a desktop-like backdrop.
@MainActor func renderUICommand() throws {
    let out = URL(fileURLWithPath: option("--out") ?? ".context/ui")
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (name, view) in PanelGallery.states() + SetupGallery.states() + SettingsGallery.states() {
        for scheme in [ColorScheme.light, .dark] {
            let backdrop = scheme == .light ? Color(white: 0.91) : Color(white: 0.07)
            guard let png = Snapshot.png(view.padding(24).background(backdrop), scheme: scheme) else { fail("couldn't render \(name)") }
            let file = out.appendingPathComponent("\(name)-\(scheme == .light ? "light" : "dark").png")
            try png.write(to: file)
            print(file.path)
        }
    }
}
