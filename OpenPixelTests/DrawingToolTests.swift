import XCTest
@testable import OpenPixel

final class ShapeRasterTests: XCTestCase {
    func testBrushOffsets() {
        XCTAssertEqual(Raster.brushOffsets(size: 1, shape: .square), [PixelPoint(x: 0, y: 0)])
        XCTAssertEqual(Raster.brushOffsets(size: 3, shape: .square).count, 9)
        XCTAssertEqual(Raster.brushOffsets(size: 3, shape: .circle).count, 9)
        // A 4 px circle drops the four corners.
        XCTAssertEqual(Raster.brushOffsets(size: 4, shape: .circle).count, 12)
        // Odd sizes are centred.
        let offsets = Raster.brushOffsets(size: 3, shape: .square)
        XCTAssertEqual(offsets.map(\.x).min(), -1)
        XCTAssertEqual(offsets.map(\.x).max(), 1)
    }

    func testRectangle() {
        let outline = Set(Raster.rectangle(from: PixelPoint(x: 3, y: 3), to: PixelPoint(x: 0, y: 0), filled: false))
        XCTAssertEqual(outline.count, 12)
        XCTAssertFalse(outline.contains(PixelPoint(x: 1, y: 1)))
        XCTAssertEqual(Raster.rectangle(from: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 3, y: 3), filled: true).count, 16)
    }

    func testEllipseStaysInsideItsBoxAndIsSymmetric() {
        let points = Set(Raster.ellipse(from: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 8, y: 4), filled: false))
        XCTAssertEqual(points.map(\.x).min(), 0)
        XCTAssertEqual(points.map(\.x).max(), 8)
        XCTAssertEqual(points.map(\.y).min(), 0)
        XCTAssertEqual(points.map(\.y).max(), 4)
        for p in points {
            XCTAssertTrue(points.contains(PixelPoint(x: 8 - p.x, y: p.y)), "not mirrored horizontally at \(p)")
            XCTAssertTrue(points.contains(PixelPoint(x: p.x, y: 4 - p.y)), "not mirrored vertically at \(p)")
        }
        let filled = Set(Raster.ellipse(from: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 8, y: 4), filled: true))
        XCTAssertTrue(filled.contains(PixelPoint(x: 4, y: 2)))
        XCTAssertTrue(filled.isSuperset(of: points))
    }

    func testTinyEllipses() {
        XCTAssertEqual(Set(Raster.ellipse(from: PixelPoint(x: 2, y: 2), to: PixelPoint(x: 2, y: 2), filled: false)), [PixelPoint(x: 2, y: 2)])
        XCTAssertEqual(Set(Raster.ellipse(from: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 1, y: 1), filled: false)).count, 4)
    }

    func testReplaceColorIsGlobal() {
        var image = PixelImage(width: 5, height: 1)
        image[0, 0] = .black
        image[4, 0] = .black
        Raster.replaceColor(&image, at: PixelPoint(x: 0, y: 0), with: .white)
        XCTAssertEqual(image[4, 0], .white)
        XCTAssertEqual(image[2, 0], .clear)
    }
}

@MainActor
final class DrawingToolDocumentTests: XCTestCase {
    private func makeDocument(size: Int = 8) -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: size, height: size, background: nil, palette: []))
        doc.primary = .black
        return doc
    }

    private func painted(_ doc: SpriteDocument) -> Set<PixelPoint> {
        let image = doc.sprite.composite(frameIndex: doc.activeFrameIndex)
        var points = Set<PixelPoint>()
        for y in 0..<image.height {
            for x in 0..<image.width where !image[x, y].isTransparent {
                points.insert(PixelPoint(x: x, y: y))
            }
        }
        return points
    }

    func testPixelPerfectRemovesCorners() {
        let doc = makeDocument()
        // An L-shaped staircase: (0,0) (1,0) (1,1) (2,1) (2,2)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        for p in [(1, 0), (1, 1), (2, 1), (2, 2)] { doc.continueStroke(to: PixelPoint(x: p.0, y: p.1)) }
        doc.endStroke()
        XCTAssertEqual(painted(doc), [PixelPoint(x: 0, y: 0), PixelPoint(x: 1, y: 1), PixelPoint(x: 2, y: 2)])

        let plain = makeDocument()
        plain.pixelPerfect = false
        plain.beginStroke(at: PixelPoint(x: 0, y: 0))
        for p in [(1, 0), (1, 1), (2, 1), (2, 2)] { plain.continueStroke(to: PixelPoint(x: p.0, y: p.1)) }
        plain.endStroke()
        XCTAssertEqual(painted(plain).count, 5)
    }

    func testPixelPerfectKeepsWhatWasUnderneath() {
        let doc = makeDocument()
        doc.primary = .white
        doc.beginStroke(at: PixelPoint(x: 1, y: 0))
        doc.endStroke()
        doc.primary = .black
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 1, y: 0))
        doc.continueStroke(to: PixelPoint(x: 1, y: 1))
        doc.endStroke()
        XCTAssertEqual(doc.sprite.composite(frameIndex: 0)[1, 0], .white)
    }

    func testBrushSizeStampsSquare() {
        let doc = makeDocument()
        doc.setBrushSize(3)
        doc.beginStroke(at: PixelPoint(x: 4, y: 4))
        doc.endStroke()
        XCTAssertEqual(painted(doc).count, 9)
        doc.setBrushSize(99)
        XCTAssertEqual(doc.brushSize, SpriteDocument.maxBrushSize)
    }

    func testShapePreviewIsReplacedWhileDraggingAndUndoesInOneStep() {
        let doc = makeDocument()
        doc.select(.rectangle)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 7, y: 7))
        doc.continueStroke(to: PixelPoint(x: 2, y: 2))
        doc.endStroke()
        XCTAssertEqual(painted(doc).count, 8)
        XCTAssertFalse(painted(doc).contains(PixelPoint(x: 7, y: 7)))
        doc.undo()
        XCTAssertTrue(painted(doc).isEmpty)
        XCTAssertFalse(doc.canUndo)
    }

    func testFilledEllipseAndLineTool() {
        let doc = makeDocument()
        doc.select(.ellipse)
        doc.shapeFilled = true
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 6, y: 6))
        doc.endStroke()
        XCTAssertTrue(painted(doc).contains(PixelPoint(x: 3, y: 3)))

        let line = makeDocument()
        line.select(.line)
        line.beginStroke(at: PixelPoint(x: 0, y: 0))
        line.continueStroke(to: PixelPoint(x: 7, y: 0))
        line.endStroke()
        XCTAssertEqual(painted(line).count, 8)
    }

    func testNonContiguousBucket() {
        let doc = makeDocument(size: 4)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.endStroke()
        doc.beginStroke(at: PixelPoint(x: 3, y: 3))
        doc.endStroke()
        doc.select(.bucket)
        doc.fillContiguous = false
        doc.primary = .white
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        XCTAssertEqual(doc.sprite.composite(frameIndex: 0)[3, 3], .white)
    }
}
