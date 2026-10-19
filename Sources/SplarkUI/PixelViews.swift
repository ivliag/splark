import SplarkKit
import SwiftUI

/// A 1-bit pixel grid, drawn crisply: one grid pixel is `scale` points. Its colour is the foreground style.
public struct PixelGridView: View {
    let grid: PixelGrid
    let level: SparkLevel
    let scale: CGFloat

    public init(grid: PixelGrid, level: SparkLevel = .bright, scale: CGFloat = 1) {
        self.grid = grid
        self.level = level
        self.scale = scale
    }

    public var body: some View {
        Canvas { context, _ in
            var path = Path()
            for point in grid.litPoints(level: level) {
                path.addRect(CGRect(x: CGFloat(point.x) * scale, y: CGFloat(point.y) * scale, width: scale, height: scale))
            }
            context.fill(path, with: .foreground)
        }
        .frame(width: CGFloat(grid.width) * scale, height: CGFloat(grid.height) * scale)
        .accessibilityHidden(true)
    }
}

/// The soft spark at a level (spec §4.1).
public struct SparkView: View {
    let level: SparkLevel
    let scale: CGFloat

    public init(level: SparkLevel, scale: CGFloat = 1) {
        self.level = level
        self.scale = scale
    }

    public var body: some View { PixelGridView(grid: PixelArt.spark, level: level, scale: scale) }
}

/// Text in the 5×7 pixel font: workspace initials, step numbers.
public struct PixelText: View {
    let text: String
    let scale: CGFloat

    public init(_ text: String, scale: CGFloat = 2) {
        self.text = text
        self.scale = scale
    }

    public var body: some View { PixelGridView(grid: PixelFont.text(text), scale: scale) }
}

/// The spark cycling through its three levels while Splark works (spec §4.3: "with a cycling spark").
public struct CyclingSpark: View {
    public init() {}

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 0.35)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
            SparkView(level: [SparkLevel.dimmed, .brighter, .bright][step])
        }
    }
}
