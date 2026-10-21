import CoreGraphics
import Foundation

/// The "Graphite" app icon (spec §4.1), drawn from the same pixel definitions as the menu-bar spark.
///
/// The design is a 100-unit square: a rounded rectangle (radius 22.4) with a vertical gradient from #3a3a40 to #26262b,
/// and over its inner 80 units a 40×40 grid: the soft spark at twice its size in #e6e6ea, and around it three dithered
/// glow rings in #9c9ca4 (50% up to 2 cells out, 25% up to 3.6, sparse up to 5). Rendered inside Apple's macOS icon grid
/// (the tile is 824 of 1024), like other apps' icons.
public enum AppIconArt {
    public enum Cell: Sendable, Equatable { case off, core, glow }

    static let gridSize = 40, sparkOffset = 9

    private static func isSpark(_ x: Int, _ y: Int) -> Bool {
        guard x >= sparkOffset, y >= sparkOffset, x < sparkOffset + 22, y < sparkOffset + 22 else { return false }
        return PixelArt.spark[(x - sparkOffset) / 2, (y - sparkOffset) / 2]
    }

    /// One cell of the 40×40 grid, exactly as the prototype draws it.
    public static func cell(x: Int, y: Int) -> Cell {
        var distance = 99.0
        outer: for dy in -5...5 {
            for dx in -5...5 where isSpark(x + dx, y + dy) {
                distance = min(distance, hypot(Double(dx), Double(dy)))
                if distance == 0 { break outer }
            }
        }
        switch distance {
        case 0: return .core
        case ...2: return (x + y) % 2 == 0 ? .glow : .off
        case ...3.6: return x % 2 == 0 && y % 2 == 0 ? .glow : .off
        case ...5: return x % 4 == 0 && y % 4 == 2 ? .glow : .off
        default: return .off
        }
    }

    /// The icon as a `size`×`size` bitmap with a transparent margin.
    public static func cgImage(size: Int) -> CGImage {
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // 100 design units across the 824/1024 tile, centred; flip so y runs downwards, as in the design.
        let unit = CGFloat(size) * 824 / 1024 / 100
        let inset = CGFloat(size) * 100 / 1024
        context.translateBy(x: inset, y: CGFloat(size) - inset)
        context.scaleBy(x: unit, y: -unit)

        let tile = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 100, height: 100), cornerWidth: 22.4, cornerHeight: 22.4, transform: nil)
        context.addPath(tile)
        context.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [rgb(0x3a3a40), rgb(0x26262b)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 100), options: [])

        context.setShouldAntialias(size < 128)   // crisp pixels where a cell is 2 device pixels or more; soft below that
        for y in 0..<gridSize {
            for x in 0..<gridSize {
                let kind = cell(x: x, y: y)
                guard kind != .off else { continue }
                context.setFillColor(kind == .core ? rgb(0xe6e6ea) : rgb(0x9c9ca4))
                context.fill(CGRect(x: 10 + CGFloat(x) * 2, y: 10 + CGFloat(y) * 2, width: 2, height: 2))
            }
        }
        return context.makeImage()!
    }

    private static func rgb(_ hex: Int) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}
