import AppKit

/// The three brightness levels. Same silhouette; only how many pixels are lit changes.
public enum SparkLevel: String, Sendable, CaseIterable, Codable {
    case dimmed    // just comments: 25% (odd x and odd y)
    case brighter  // question for you: outline + 50% checker inside
    case bright    // needs action: every pixel
}

public struct PixelPoint: Hashable, Sendable {
    public let x: Int
    public let y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

/// A 1-bit pixel grid authored as rows of "#" (lit) and "." (unlit).
public struct PixelGrid: Sendable, Equatable {
    public let width: Int
    public let height: Int
    private let bits: [Bool]

    public init(rows: [String]) {
        precondition(!rows.isEmpty && rows.allSatisfy { $0.count == rows[0].count }, "rows must form a non-empty rectangle")
        height = rows.count
        width = rows[0].count
        bits = rows.flatMap { $0.map { $0 == "#" } }
    }

    public subscript(x: Int, y: Int) -> Bool {
        x >= 0 && y >= 0 && x < width && y < height && bits[y * width + x]
    }

    public func isLit(x: Int, y: Int, level: SparkLevel) -> Bool {
        guard self[x, y] else { return false }
        switch level {
        case .bright: return true
        case .dimmed: return x % 2 == 1 && y % 2 == 1
        case .brighter:
            let edge = !self[x - 1, y] || !self[x + 1, y] || !self[x, y - 1] || !self[x, y + 1]
            return edge || (x + y) % 2 == 0
        }
    }

    public func litPoints(level: SparkLevel) -> [PixelPoint] {
        (0..<height).flatMap { y in (0..<width).compactMap { x in isLit(x: x, y: y, level: level) ? PixelPoint(x: x, y: y) : nil } }
    }

    /// Rows of "#"/"." for the given level. Handy for tests and debugging.
    public func rendered(level: SparkLevel) -> [String] {
        (0..<height).map { y in String((0..<width).map { x in isLit(x: x, y: y, level: level) ? "#" : "." }) }
    }
}

public enum PixelArt {
    /// The soft spark, 11×11 (spec §4.1).
    public static let spark = PixelGrid(rows: [
        ".....#.....",
        ".....#.....",
        "....###....",
        "...#####...",
        "..#######..",
        "###########",
        "..#######..",
        "...#####...",
        "....###....",
        ".....#.....",
        ".....#.....",
    ])

    /// Renders a grid at `scale` points per pixel. Template images are tinted by AppKit (menu bar).
    /// A 7×7 pixel circle: setup's progress dots.
    public static let dot = PixelGrid(rows: [
        "..###..",
        ".#####.",
        "#######",
        "#######",
        "#######",
        ".#####.",
        "..###..",
    ])

    public static func image(_ grid: PixelGrid, level: SparkLevel, scale: CGFloat = 1, color: NSColor = .black, template: Bool = false) -> NSImage {
        let size = NSSize(width: CGFloat(grid.width) * scale, height: CGFloat(grid.height) * scale)
        let points = grid.litPoints(level: level)
        let image = NSImage(size: size, flipped: true) { _ in
            color.setFill()
            for p in points {
                NSRect(x: CGFloat(p.x) * scale, y: CGFloat(p.y) * scale, width: scale, height: scale).fill()
            }
            return true
        }
        image.isTemplate = template
        return image
    }
}
