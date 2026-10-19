import AppKit
import SwiftUI

/// A colour from the prototypes: a hex RGB value and an opacity. Usable anywhere SwiftUI takes a `ShapeStyle`.
public struct Ink: ShapeStyle, Equatable, Sendable {
    public let hex: Int
    public let opacity: Double

    public init(_ hex: Int, opacity: Double = 1) {
        self.hex = hex
        self.opacity = opacity
    }

    public var color: Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: opacity)
    }

    public func resolve(in environment: EnvironmentValues) -> Color { color }
}

/// The prototypes' palette (spec §4.1), light and dark. Views take it from the colour scheme: `Palette(scheme)`.
public struct Palette: Equatable, Sendable {
    public let text, secondary, tertiary, spark: Ink
    public let rowHover, separator, chip, chipHover, inputBackground, panelBackground, panelBorder, knock, toastBackground: Ink

    public init(_ scheme: ColorScheme) {
        if scheme == .dark {
            text = Ink(0xdcdce0); secondary = Ink(0x98989e); tertiary = Ink(0x696970); spark = Ink(0xb4b4ba)
            rowHover = Ink(0xffffff, opacity: 0.05); separator = Ink(0xffffff, opacity: 0.08)
            chip = Ink(0xffffff, opacity: 0.08); chipHover = Ink(0xffffff, opacity: 0.15)
            inputBackground = Ink(0x000000, opacity: 0.28); panelBackground = Ink(0x26262a, opacity: 0.78)
            panelBorder = Ink(0xffffff, opacity: 0.12); knock = Ink(0x2c2c30)
        } else {
            text = Ink(0x3a3a3e); secondary = Ink(0x7d7d83); tertiary = Ink(0xadadb3); spark = Ink(0x6a6a70)
            rowHover = Ink(0x000000, opacity: 0.04); separator = Ink(0x000000, opacity: 0.07)
            chip = Ink(0x000000, opacity: 0.05); chipHover = Ink(0x000000, opacity: 0.09)
            inputBackground = Ink(0xffffff, opacity: 0.92); panelBackground = Ink(0xf8f8fa, opacity: 0.82)
            panelBorder = Ink(0x000000, opacity: 0.10); knock = Ink(0xf4f4f6)
        }
        toastBackground = Ink(0x1e1e20, opacity: 0.86)
    }
}

/// Sizes and type from the prototypes.
public enum Theme {
    public static let panelWidth: CGFloat = 372
    public static let panelCorner: CGFloat = 18
    public static let panelMaxScreenFraction: CGFloat = 0.7
    /// The CSS weight 590 of bold leads (spec §4.1), between medium and semibold.
    public static let leadWeight = NSFont.Weight(rawValue: 0.29)

    public static func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> Font {
        Font(NSFont.systemFont(ofSize: size, weight: weight))
    }
}
