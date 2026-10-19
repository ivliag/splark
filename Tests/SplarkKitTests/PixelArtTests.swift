import AppKit
import Testing
@testable import SplarkKit

@Suite struct PixelArtTests {
    @Test func brightLightsTheWholeSilhouette() {
        #expect(PixelArt.spark.rendered(level: .bright) == [
            ".....#.....", ".....#.....", "....###....", "...#####...", "..#######..", "###########",
            "..#######..", "...#####...", "....###....", ".....#.....", ".....#.....",
        ])
        #expect(PixelArt.spark.litPoints(level: .bright).count == 45)
    }

    @Test func brighterIsOutlinePlusChecker() {
        #expect(PixelArt.spark.rendered(level: .brighter) == [
            ".....#.....", ".....#.....", "....#.#....", "...#.#.#...", "..#.#.#.#..", "##.#.#.#.##",
            "..#.#.#.#..", "...#.#.#...", "....#.#....", ".....#.....", ".....#.....",
        ])
        #expect(PixelArt.spark.litPoints(level: .brighter).count == 29)
    }

    @Test func dimmedLightsOnlyOddOddPixels() {
        #expect(PixelArt.spark.rendered(level: .dimmed) == [
            "...........", ".....#.....", "...........", "...#.#.#...", "...........", ".#.#.#.#.#.",
            "...........", "...#.#.#...", "...........", ".....#.....", "...........",
        ])
        #expect(PixelArt.spark.litPoints(level: .dimmed).count == 13)
    }

    /// Setup's progress dots: a 7×7 pixel circle, at the same three levels as the spark.
    @Test func theStepDotIsAPixelCircle() {
        #expect(PixelArt.dot.rendered(level: .bright) == [
            "..###..", ".#####.", "#######", "#######", "#######", ".#####.", "..###..",
        ])
        #expect(PixelArt.dot.rendered(level: .brighter) == [
            "..###..", ".#.#.#.", "#.#.#.#", "##.#.##", "#.#.#.#", ".#.#.#.", "..###..",
        ])
        #expect(PixelArt.dot.litPoints(level: .dimmed).count == 9)
    }

    @Test func imageHasGridSizeTimesScaleAndPaintsOnlyLitPixels() throws {
        let image = PixelArt.image(PixelArt.spark, level: .bright, scale: 2, color: .black)
        #expect(image.size == NSSize(width: 22, height: 22))
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let rep = NSBitmapImageRep(cgImage: cg)
        let pxPerPoint = CGFloat(rep.pixelsWide) / image.size.width
        func alpha(atGridX x: Int, y: Int) -> CGFloat {
            let px = Int((CGFloat(x) * 2 + 1) * pxPerPoint), py = Int((CGFloat(y) * 2 + 1) * pxPerPoint)
            return rep.colorAt(x: px, y: py)?.alphaComponent ?? 0
        }
        #expect(alpha(atGridX: 5, y: 5) > 0.9)   // centre is lit
        #expect(alpha(atGridX: 0, y: 0) < 0.1)   // corner is not
    }

    @Test func templateFlagIsPassedThrough() {
        #expect(PixelArt.image(PixelArt.spark, level: .dimmed, template: true).isTemplate)
    }
}
