import XCTest
@testable import OpenPixel

final class FillRegionTests: XCTestCase {
    func testToleranceAndDiagonals() {
        var image = PixelImage(width: 3, height: 3, fill: .white)
        image[1, 0] = .black; image[1, 1] = .black; image[0, 1] = .black   // walls around the top-left corner
        image[2, 2] = PixelColor(r: 250, g: 250, b: 250)
        let start = PixelPoint(x: 2, y: 0)
        let plain = Raster.fillRegion(in: image, at: start)
        XCTAssertFalse(plain[0, 0], "walled off")
        XCTAssertFalse(plain[2, 2], "a slightly different white")
        XCTAssertTrue(Raster.fillRegion(in: image, at: start, tolerance: 8)[2, 2])
        XCTAssertFalse(Raster.fillRegion(in: image, at: start, tolerance: 8, diagonal: true)[0, 0],
                       "(0, 0) only touches (1, 1), which is black")
        var gap = PixelImage(width: 2, height: 2, fill: .white)
        gap[1, 0] = .black; gap[0, 1] = .black
        XCTAssertFalse(Raster.fillRegion(in: gap, at: PixelPoint(x: 0, y: 0))[1, 1])
        XCTAssertTrue(Raster.fillRegion(in: gap, at: PixelPoint(x: 0, y: 0), diagonal: true)[1, 1], "through the corner")
    }
}

@MainActor
final class BucketOptionsDocumentTests: XCTestCase {
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 6, height: 6, background: nil, palette: []))
        doc.primary = .black
        return doc
    }

    private func pixel(_ doc: SpriteDocument, layer: Int = 0, _ x: Int, _ y: Int) -> PixelColor {
        doc.sprite.cel(layer: doc.sprite.layers[layer].id, frame: doc.activeFrame.id)?[x, y] ?? .clear
    }

    private func tap(_ doc: SpriteDocument, _ x: Int, _ y: Int) {
        doc.beginStroke(at: PixelPoint(x: x, y: y))
        doc.endStroke()
    }

    func testFillCanReferToEveryVisibleLayer() {
        let doc = makeDocument()
        // A vertical wall on the bottom layer.
        doc.select(.line)
        doc.beginStroke(at: PixelPoint(x: 3, y: 0))
        doc.continueStroke(to: PixelPoint(x: 3, y: 5))
        doc.endStroke()
        doc.addLayer()
        doc.primary = .white
        doc.select(.bucket)
        tap(doc, 0, 0)
        XCTAssertEqual(pixel(doc, layer: 1, 5, 5), .white, "the empty top layer fills completely")
        doc.undo()
        doc.fillSampleAllLayers = true
        tap(doc, 0, 0)
        XCTAssertEqual(pixel(doc, layer: 1, 2, 5), .white)
        XCTAssertEqual(pixel(doc, layer: 1, 5, 5), .clear, "stopped by the wall below")
        XCTAssertEqual(pixel(doc, layer: 0, 0, 0), .clear, "only the active layer is painted")
    }

    func testEyedropperCanReadOnlyTheActiveLayer() {
        let doc = makeDocument()
        tap(doc, 0, 0)
        doc.addLayer()
        doc.primary = .white
        doc.pickColor(at: PixelPoint(x: 0, y: 0))
        XCTAssertEqual(doc.primary, .black)
        doc.primary = .white
        doc.eyedropperActiveLayer = true
        doc.pickColor(at: PixelPoint(x: 0, y: 0))
        XCTAssertEqual(doc.primary, .white, "the active layer is empty there")
    }
}
