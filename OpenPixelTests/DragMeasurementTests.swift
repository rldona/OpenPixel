import XCTest
@testable import OpenPixel

@MainActor
final class DragMeasurementTests: XCTestCase {
    func testLineSizeLengthAndAngle() {
        XCTAssertEqual(DragMeasurement(lineFrom: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 11, y: 0)).text, "12 × 1 · 12 px · 0°")
        XCTAssertEqual(DragMeasurement(lineFrom: PixelPoint(x: 0, y: 4), to: PixelPoint(x: 4, y: 0)).text, "5 × 5 · 5 px · 45°")
        XCTAssertEqual(DragMeasurement(lineFrom: PixelPoint(x: 4, y: 0), to: PixelPoint(x: 0, y: 0)).text, "5 × 1 · 5 px · 180°")
        XCTAssertEqual(DragMeasurement(lineFrom: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 0, y: 3)).text, "1 × 4 · 4 px · -90°")
    }

    func testRectangleShowsWhileDraggingAndGoesAway() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 32, height: 32, background: nil, palette: []))
        doc.select(.rectangle)
        doc.beginStroke(at: PixelPoint(x: 10, y: 10))
        doc.continueStroke(to: PixelPoint(x: 3, y: 5))
        XCTAssertEqual(doc.dragMeasurement?.text, "8 × 6")
        XCTAssertEqual(doc.dragMeasurement?.origin, PixelPoint(x: 10, y: 10), "the label goes by where the drag began")
        doc.endStroke()
        XCTAssertNil(doc.dragMeasurement)
    }

    func testMarqueeIsClippedToTheSpriteAndFillsTheBar() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 16, height: 16, background: nil, palette: []))
        doc.selectionFitsContent = false
        doc.select(.selectRectangle)
        doc.beginStroke(at: PixelPoint(x: 4, y: 2))
        doc.continueStroke(to: PixelPoint(x: 30, y: 6))
        XCTAssertEqual(doc.dragMeasurement?.text, "12 × 5", "only the part inside the sprite is selected")
        XCTAssertNil(doc.selectionBounds, "the bar waits for the drag to end")
        doc.endStroke()
        XCTAssertNil(doc.dragMeasurement)
        XCTAssertEqual(doc.selectionBounds, PixelRect(minX: 4, minY: 2, maxX: 15, maxY: 6))
        doc.deselect()
        XCTAssertNil(doc.selectionBounds)
    }

    func testCancelledMarqueeHidesTheLabel() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 16, height: 16, background: nil, palette: []))
        doc.select(.lasso)
        doc.beginStroke(at: PixelPoint(x: 1, y: 1))
        doc.continueStroke(through: [PixelPoint(x: 6, y: 1), PixelPoint(x: 6, y: 4)])
        XCTAssertEqual(doc.dragMeasurement?.text, "6 × 4")
        doc.cancelStroke()
        XCTAssertNil(doc.dragMeasurement)
    }
}
