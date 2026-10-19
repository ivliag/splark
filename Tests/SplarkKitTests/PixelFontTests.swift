import AppKit
import Testing
@testable import SplarkKit

@Suite struct PixelFontTests {
    @Test func glyphsMatchThePrototype() {
        #expect(PixelFont.glyph("L").rendered(level: .bright) == ["#....", "#....", "#....", "#....", "#....", "#....", "#####"])
        #expect(PixelFont.glyph("I").rendered(level: .bright) == ["###", ".#.", ".#.", ".#.", ".#.", ".#.", "###"])
        #expect(PixelFont.glyph("2").rendered(level: .bright) == [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"])
    }

    @Test func coversLettersAndDigitsInSevenRows() {
        for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+?" {
            #expect(PixelFont.glyph(ch).height == 7, "\(ch)")
            #expect(PixelFont.glyph(ch).litPoints(level: .bright).count > 0, "\(ch)")
        }
        #expect(Set("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".map { PixelFont.glyph($0).rendered(level: .bright) }).count == 36)
    }

    @Test func lowercaseIsUppercaseAndUnknownIsAQuestionMark() {
        #expect(PixelFont.glyph("l") == PixelFont.glyph("L"))
        #expect(PixelFont.glyph("ж") == PixelFont.glyph("?"))
    }

    @Test func textSetsGlyphsSideBySideWithAGap() {
        let lc = PixelFont.text("LC")
        #expect(lc.width == 5 + 1 + 5 && lc.height == 7)
        #expect(lc.rendered(level: .bright)[6] == "#####..###.")
    }
}

@Suite struct AppIconArtTests {
    @Test func theSparkSitsAtTwiceItsSizeInTheMiddle() {
        #expect(AppIconArt.cell(x: 19, y: 19) == .core)
        #expect(AppIconArt.cell(x: 0, y: 0) == .off)
        var cores = 0
        for y in 0..<40 { for x in 0..<40 where AppIconArt.cell(x: x, y: y) == .core { cores += 1 } }
        #expect(cores == 45 * 4)
    }

    @Test func glowRingsAreDitheredAsInThePrototype() {
        // (9, 19) is the spark's left tip; one cell further left is in the 50% ring, on even x+y only.
        #expect(AppIconArt.cell(x: 9, y: 19) == .core)
        #expect(AppIconArt.cell(x: 8, y: 19) == .off)          // 8 + 19 is odd
        #expect(AppIconArt.cell(x: 7, y: 19) == .glow)         // distance 2, 7 + 19 even
        #expect(AppIconArt.cell(x: 6, y: 18) == .glow)         // distance ~3.2: the 25% ring, even x and even y
        #expect(AppIconArt.cell(x: 16, y: 6) == .glow)         // distance ~4.2: the sparse ring, x % 4 == 0 and y % 4 == 2
        #expect(AppIconArt.cell(x: 5, y: 18) == .off)          // distance ~4.1, but not on the sparse grid
        #expect(AppIconArt.cell(x: 4, y: 18) == .off)          // just over 5 cells out
    }

    @Test func rendersAtAnySizeInsideApplesIconGrid() throws {
        let image = AppIconArt.cgImage(size: 1024)
        #expect(image.width == 1024 && image.height == 1024)
        let rep = NSBitmapImageRep(cgImage: image)
        #expect((rep.colorAt(x: 40, y: 40)?.alphaComponent ?? 1) < 0.01)            // outside the tile: transparent
        // colorAt gives the stored sRGB components (converting them again would shift them).
        let center = try #require(rep.colorAt(x: 512, y: 512))
        #expect(abs(center.redComponent - 0xe6 / 255.0) < 0.02)                        // the spark's core colour
        let tile = try #require(rep.colorAt(x: 512, y: 140))                           // near the top: the gradient's lighter end
        #expect(tile.alphaComponent > 0.99 && abs(tile.redComponent - 0x3a / 255.0) < 0.04)
        #expect(AppIconArt.cgImage(size: 16).width == 16)
    }
}

