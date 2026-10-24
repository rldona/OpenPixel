import XCTest
@testable import OpenPixel

final class SymmetryModelTests: XCTestCase {
    func testImagesAroundTheCentre() {
        var s = Symmetry(isEnabled: true)
        XCTAssertEqual(s.images(of: PixelPoint(x: 1, y: 2), width: 8, height: 8), [PixelPoint(x: 6, y: 2)])
        s.vertical = true
        XCTAssertEqual(Set(s.images(of: PixelPoint(x: 1, y: 2), width: 8, height: 8)),
                       [PixelPoint(x: 6, y: 2), PixelPoint(x: 1, y: 5), PixelPoint(x: 6, y: 5)])
        s.horizontal = false
        XCTAssertEqual(s.images(of: PixelPoint(x: 1, y: 2), width: 8, height: 8), [PixelPoint(x: 1, y: 5)])
        s.isEnabled = false
        XCTAssertEqual(s.images(of: PixelPoint(x: 1, y: 2), width: 8, height: 8), [])
    }

    func testMovedAndMidPixelAxes() {
        // Axis between pixels 1 and 2.
        var s = Symmetry(isEnabled: true, axisX2: 4)
        XCTAssertEqual(s.images(of: PixelPoint(x: 0, y: 0), width: 8, height: 8), [PixelPoint(x: 3, y: 0)])
        // Axis through the middle of pixel 2: that pixel is its own mirror.
        s.axisX2 = 5
        XCTAssertEqual(s.images(of: PixelPoint(x: 2, y: 0), width: 8, height: 8), [PixelPoint(x: 2, y: 0)])
        XCTAssertEqual(s.images(of: PixelPoint(x: 0, y: 0), width: 8, height: 8), [PixelPoint(x: 4, y: 0)])
    }

    func testCoveringIncludesTheMirroredArea() {
        let s = Symmetry(isEnabled: true, vertical: true)
        let r = s.covering(PixelRect(minX: 0, minY: 0, maxX: 1, maxY: 1), width: 8, height: 8)
        XCTAssertEqual(r, PixelRect(minX: 0, minY: 0, maxX: 7, maxY: 7))
    }
}

@MainActor
final class SymmetryDocumentTests: XCTestCase {
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 8, background: nil, palette: []))
        doc.primary = .black
        return doc
    }

    private func pixel(_ doc: SpriteDocument, _ x: Int, _ y: Int) -> PixelColor {
        doc.sprite.cel(layer: doc.activeLayerID, frame: doc.activeFrame.id)?[x, y] ?? .clear
    }

    func testBothAxesPaintFourCopies() {
        let doc = makeDocument()
        doc.symmetry = Symmetry(isEnabled: true, horizontal: true, vertical: true)
        doc.beginStroke(at: PixelPoint(x: 1, y: 1))
        doc.endStroke()
        for p in [(1, 1), (6, 1), (1, 6), (6, 6)] { XCTAssertEqual(pixel(doc, p.0, p.1), .black, "\(p)") }
    }

    func testDraggedAxisIsClampedToTheSprite() {
        let doc = makeDocument()
        doc.symmetry.isEnabled = true
        doc.moveSymmetryAxis(vertical: false, to: 6)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.endStroke()
        XCTAssertEqual(pixel(doc, 5, 0), .black)
        doc.moveSymmetryAxis(vertical: false, to: 100)
        XCTAssertEqual(doc.symmetry.axisX2, 15)
        doc.moveSymmetryAxis(vertical: false, to: -3)
        XCTAssertEqual(doc.symmetry.axisX2, 1)
        doc.centerSymmetryAxes()
        XCTAssertNil(doc.symmetry.axisX2)
    }

    func testCopiesOutsideTheSpriteAreSkipped() {
        let doc = makeDocument()
        doc.symmetry.isEnabled = true
        doc.moveSymmetryAxis(vertical: false, to: 2)
        doc.beginStroke(at: PixelPoint(x: 6, y: 3))
        doc.endStroke()
        XCTAssertEqual(pixel(doc, 6, 3), .black)
    }

    func testShapesArePaintedSymmetrically() {
        let doc = makeDocument()
        doc.symmetry = Symmetry(isEnabled: true, horizontal: false, vertical: true)
        doc.select(.line)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 3, y: 0))
        doc.endStroke()
        XCTAssertEqual(pixel(doc, 2, 7), .black)
    }
}
