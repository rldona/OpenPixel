import XCTest
@testable import OpenPixel

final class LineBrushTests: XCTestCase {
    func testLineBrushFollowsItsAngle() {
        XCTAssertEqual(Set(Raster.brushOffsets(size: 5, shape: .line, angle: 0)), Set((-2...2).map { PixelPoint(x: $0, y: 0) }))
        XCTAssertEqual(Set(Raster.brushOffsets(size: 5, shape: .line, angle: 90)), Set((-2...2).map { PixelPoint(x: 0, y: $0) }))
        // 45°: up and to the right.
        let diagonal = Set(Raster.brushOffsets(size: 5, shape: .line, angle: 45))
        XCTAssertTrue(diagonal.contains(PixelPoint(x: 1, y: -1)))
        XCTAssertTrue(diagonal.contains(PixelPoint(x: -1, y: 1)))
        XCTAssertEqual(Raster.brushOffsets(size: 1, shape: .line, angle: 30), [PixelPoint(x: 0, y: 0)])
    }
}

@MainActor
final class BrushDocumentTests: XCTestCase {
    private let red = PixelColor(r: 255, g: 0, b: 0)

    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 12, height: 12, background: nil, palette: []))
        doc.primary = .black
        return doc
    }

    private func pixel(_ doc: SpriteDocument, _ x: Int, _ y: Int) -> PixelColor {
        doc.sprite.cel(layer: doc.activeLayerID, frame: doc.activeFrame.id)?[x, y] ?? .clear
    }

    private func dot(_ doc: SpriteDocument, _ x: Int, _ y: Int) {
        doc.beginStroke(at: PixelPoint(x: x, y: y))
        doc.endStroke()
    }

    func testLineBrushStroke() {
        let doc = makeDocument()
        doc.setBrushSize(3)
        doc.brushShape = .line
        doc.brushAngle = 90
        dot(doc, 5, 5)
        XCTAssertEqual(pixel(doc, 5, 4), .black)
        XCTAssertEqual(pixel(doc, 5, 6), .black)
        XCTAssertEqual(pixel(doc, 4, 5), .clear)
    }

    /// A 2×1 brush: red on the left, black on the right.
    private func makeBrush(_ doc: SpriteDocument) {
        doc.primary = red
        dot(doc, 0, 0)
        doc.primary = .black
        dot(doc, 1, 0)
        doc.select(.selectRectangle)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 3, y: 2))
        doc.endStroke()
        doc.newBrushFromSelection()
    }

    func testCustomBrushStampsItsOwnColors() {
        let doc = makeDocument()
        makeBrush(doc)
        XCTAssertEqual(doc.customBrush?.width, 2, "trimmed to what's drawn")
        XCTAssertEqual(doc.customBrush?.height, 1)
        XCTAssertTrue(doc.useCustomBrush)
        XCTAssertEqual(doc.tool, .pencil)
        XCTAssertFalse(doc.hasSelection)
        dot(doc, 6, 6)
        XCTAssertEqual(pixel(doc, 6, 6), red)
        XCTAssertEqual(pixel(doc, 7, 6), .black)

        doc.customBrushUsesColor = true
        doc.primary = .white
        dot(doc, 6, 9)
        XCTAssertEqual(pixel(doc, 6, 9), .white)
        XCTAssertEqual(pixel(doc, 7, 9), .white)

        doc.useCustomBrush = false
        dot(doc, 10, 10)
        XCTAssertEqual(pixel(doc, 11, 10), .clear, "back to the 1 px pencil")
    }

    func testCustomBrushDraggedLeavesTheLastStampOnTop() {
        let doc = makeDocument()
        makeBrush(doc)
        doc.beginStroke(at: PixelPoint(x: 4, y: 8))
        doc.continueStroke(to: PixelPoint(x: 5, y: 8))
        doc.endStroke()
        XCTAssertEqual(pixel(doc, 5, 8), red, "the second stamp's red covers the first one's black")
        XCTAssertEqual(pixel(doc, 6, 8), .black)
    }

    func testNewBrushNeedsSomethingDrawn() {
        let doc = makeDocument()
        doc.select(.selectRectangle)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 3, y: 3))
        doc.endStroke()
        doc.newBrushFromSelection()
        XCTAssertNil(doc.customBrush)
        XCTAssertNotNil(doc.notice)
    }

    func testSprayStaysWithinItsWidth() {
        let doc = makeDocument()
        doc.select(.spray)
        doc.sprayWidth = 2
        doc.spraySpeed = 20
        doc.beginStroke(at: PixelPoint(x: 6, y: 6))
        doc.continueStroke(to: PixelPoint(x: 6, y: 6))
        doc.endStroke()
        var painted = 0
        for y in 0..<12 {
            for x in 0..<12 where pixel(doc, x, y) == .black {
                painted += 1
                XCTAssertLessThanOrEqual(max(abs(x - 6), abs(y - 6)), 2)
            }
        }
        XCTAssertGreaterThan(painted, 3)
        doc.undo()
        XCTAssertNil(doc.sprite.cel(layer: doc.activeLayerID, frame: doc.activeFrame.id))
    }
}
