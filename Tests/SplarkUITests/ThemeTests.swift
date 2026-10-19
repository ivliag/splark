import AppKit
import SwiftUI
import Testing
@testable import SplarkKit
@testable import SplarkUI

/// Reads one pixel of a PNG rendered by `Snapshot`, as stored (0–255).
func pixel(_ png: Data, x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    let rep = NSBitmapImageRep(data: png)!
    let c = rep.colorAt(x: x, y: y)!
    return (Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()), Int((c.alphaComponent * 255).rounded()))
}

@MainActor @Suite struct ThemeTests {
    @Test func thePaletteIsTheSpecs() {
        #expect(Palette(.light).text.hex == 0x3a3a3e && Palette(.dark).text.hex == 0xdcdce0)
        #expect(Palette(.light).secondary.hex == 0x7d7d83 && Palette(.dark).secondary.hex == 0x98989e)
        #expect(Palette(.light).tertiary.hex == 0xadadb3 && Palette(.dark).tertiary.hex == 0x696970)
        #expect(Palette(.light).spark.hex == 0x6a6a70 && Palette(.dark).spark.hex == 0xb4b4ba)
    }

    @Test func thePanelIsThePrototypesSize() {
        #expect(Theme.panelWidth == 372 && Theme.panelCorner == 18)
    }

    @Test func sparkViewDrawsCrispPixelsAtTheGivenScale() throws {
        let png = try #require(Snapshot.png(SparkView(level: .bright, scale: 2).foregroundStyle(.black), scheme: .light, scale: 1))
        let rep = try #require(NSBitmapImageRep(data: png))
        #expect(rep.pixelsWide == 22 && rep.pixelsHigh == 22)
        #expect(pixel(png, x: 11, y: 11).a == 255)        // the centre is lit
        #expect(pixel(png, x: 0, y: 0).a == 0)            // the corner isn't
        #expect(pixel(png, x: 10, y: 1).a == 255 && pixel(png, x: 9, y: 1).a == 0)   // the tip is exactly two pixels wide
    }

    @Test func pixelTextIsSevenRowsHigh() throws {
        let png = try #require(Snapshot.png(PixelText("LC", scale: 2).foregroundStyle(.black), scheme: .light, scale: 1))
        let rep = try #require(NSBitmapImageRep(data: png))
        #expect(rep.pixelsWide == (5 + 1 + 5) * 2 && rep.pixelsHigh == 14)
    }

    @Test func snapshotsRenderInDarkMode() throws {
        let png = try #require(Snapshot.png(Rectangle().fill(Palette(.dark).text).frame(width: 4, height: 4), scheme: .dark, scale: 1))
        #expect(pixel(png, x: 2, y: 2).r == 0xdc)
    }
}
