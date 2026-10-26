import XCTest
@testable import OpenPixel

@MainActor
final class OutlineTests: XCTestCase {
    /// A 5×5 image with a 1 px dot in the middle.
    private func dot() -> PixelImage {
        var image = PixelImage(width: 5, height: 5)
        image[2, 2] = .black
        return image
    }

    private func painted(_ image: PixelImage, _ color: PixelColor = .white) -> Set<[Int]> {
        Set((0..<image.height).flatMap { y in (0..<image.width).compactMap { x in image[x, y] == color ? [x, y] : nil } })
    }

    func testCircleOutlinesTheFourSides() {
        let out = OutlineEffect(color: .white).apply(to: dot(), mask: nil)
        XCTAssertEqual(painted(out), [[2, 1], [1, 2], [3, 2], [2, 3]])
        XCTAssertEqual(out[2, 2], .black, "the drawing stays")
    }

    func testSquareAddsTheCorners() {
        let out = OutlineEffect(matrix: OutlineEffect.square, color: .white).apply(to: dot(), mask: nil)
        XCTAssertEqual(painted(out).count, 8)
    }

    func testHorizontalOnlyLeftAndRight() {
        let out = OutlineEffect(matrix: OutlineEffect.horizontal, color: .white).apply(to: dot(), mask: nil)
        XCTAssertEqual(painted(out), [[1, 2], [3, 2]])
    }

    func testInsidePaintsTheEdgeOfTheDrawing() {
        var image = PixelImage(width: 5, height: 5)
        for y in 1...3 { for x in 1...3 { image[x, y] = .black } }
        let out = OutlineEffect(place: .inside, color: .white).apply(to: image, mask: nil)
        XCTAssertEqual(painted(out).count, 8, "the ring of the 3×3 block")
        XCTAssertEqual(out[2, 2], .black, "the middle has no empty neighbour")
        XCTAssertEqual(out[0, 0], .clear)
    }

    func testOnlyInsideTheSelection() {
        var mask = SelectionMask(width: 5, height: 5)
        mask[3, 2] = true
        let out = OutlineEffect(color: .white).apply(to: dot(), mask: mask)
        XCTAssertEqual(painted(out), [[3, 2]])
    }

    func testTiledWrapsAroundTheEdges() {
        var image = PixelImage(width: 5, height: 5)
        image[0, 2] = .black
        XCTAssertEqual(OutlineEffect(color: .white).apply(to: image, mask: nil)[4, 2], .clear)
        XCTAssertEqual(OutlineEffect(color: .white, tiled: true).apply(to: image, mask: nil)[4, 2], .white)
    }

    func testBackgroundColorCountsAsEmpty() {
        var image = PixelImage(width: 5, height: 5, fill: .white)
        image[2, 2] = .black
        let out = OutlineEffect(color: PixelColor(r: 255, g: 0, b: 0), background: .white).apply(to: image, mask: nil)
        XCTAssertEqual(painted(out, PixelColor(r: 255, g: 0, b: 0)).count, 4)
    }

    func testApplyIsOneUndoStepAndCancelPutsItBack() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 5, height: 5, background: nil, palette: []))
        doc.primary = .black
        doc.beginStroke(at: PixelPoint(x: 2, y: 2))
        doc.endStroke()
        let before = doc.sprite
        let effect = OutlineEffect(color: .white)
        doc.beginOutline()
        doc.previewOutline(effect, everyCel: false)
        XCTAssertEqual(doc.sprite.composite(frameIndex: 0)[2, 1], .white, "the preview shows on the canvas")
        doc.endOutline(apply: nil, everyCel: false)
        XCTAssertEqual(doc.sprite, before)
        doc.beginOutline()
        doc.endOutline(apply: effect, everyCel: false)
        XCTAssertEqual(doc.sprite.composite(frameIndex: 0)[2, 1], .white)
        doc.undo()
        XCTAssertEqual(doc.sprite, before)
    }

    func testLinkedCelsGetOneRing() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 7, height: 7, background: nil, palette: []))
        doc.primary = .black
        doc.beginStroke(at: PixelPoint(x: 3, y: 3))
        doc.endStroke()
        doc.addFrame(empty: false)
        let layer = doc.activeLayerID
        doc.isSelectingRange = true
        doc.extendRange(layer: layer, frameIndex: 0)
        doc.extendRange(layer: layer, frameIndex: 1)
        doc.linkRange()
        doc.endRangeSelection()
        doc.beginOutline()
        doc.endOutline(apply: OutlineEffect(color: .white), everyCel: true)
        let image = doc.sprite.composite(frameIndex: 1)
        XCTAssertEqual(image[3, 2], .white)
        XCTAssertEqual(image[3, 1], .clear, "not outlined twice")
    }
}
