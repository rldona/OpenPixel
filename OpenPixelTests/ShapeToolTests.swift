import XCTest
@testable import OpenPixel

final class ShapeRasterExtraTests: XCTestCase {
    func testStraightCurveIsALine() {
        let a = PixelPoint(x: 0, y: 0), b = PixelPoint(x: 6, y: 3)
        XCTAssertEqual(Set(Raster.curve(from: a, a, b, to: b)), Set(Raster.line(from: a, to: b)))
    }

    func testCurveIsConnectedAndThin() {
        let points = Raster.curve(from: PixelPoint(x: 0, y: 10), PixelPoint(x: 0, y: 0), PixelPoint(x: 10, y: 0), to: PixelPoint(x: 10, y: 10))
        XCTAssertEqual(points.first, PixelPoint(x: 0, y: 10))
        XCTAssertEqual(points.last, PixelPoint(x: 10, y: 10))
        for (p, q) in zip(points, points.dropFirst()) {
            XCTAssertLessThanOrEqual(max(abs(p.x - q.x), abs(p.y - q.y)), 1, "gap between \(p) and \(q)")
        }
        for i in 2..<points.count {
            let o = points[i - 2], p = points[i]
            XCTAssertFalse(abs(o.x - p.x) == 1 && abs(o.y - p.y) == 1 && max(abs(points[i - 1].x - o.x), abs(points[i - 1].y - o.y)) == 1
                && (points[i - 1].x == o.x || points[i - 1].y == o.y) && (points[i - 1].x == p.x || points[i - 1].y == p.y),
                           "L-corner at \(points[i - 1])")
        }
        XCTAssertTrue(points.contains { $0.y <= 3 }, "it bends towards the control points")
    }

    func testPolygonFillAndOutline() {
        let square = [PixelPoint(x: 0, y: 0), PixelPoint(x: 4, y: 0), PixelPoint(x: 4, y: 4), PixelPoint(x: 0, y: 4)]
        XCTAssertEqual(Set(Raster.polygon(square, filled: true)).count, 25)
        XCTAssertEqual(Set(Raster.polygon(square, filled: false)).count, 16)
        let triangle = Set(Raster.polygon([PixelPoint(x: 0, y: 0), PixelPoint(x: 6, y: 0), PixelPoint(x: 0, y: 6)], filled: true))
        XCTAssertTrue(triangle.contains(PixelPoint(x: 1, y: 1)))
        XCTAssertFalse(triangle.contains(PixelPoint(x: 5, y: 5)))
    }

    func testRoundedRectangle() {
        let a = PixelPoint(x: 0, y: 0), b = PixelPoint(x: 9, y: 9)
        let square = Set(Raster.rectangle(from: a, to: b, filled: true, radius: 0))
        let round = Set(Raster.rectangle(from: a, to: b, filled: true, radius: 3))
        XCTAssertEqual(square.count, 100)
        XCTAssertFalse(round.contains(a), "corners are cut")
        XCTAssertTrue(round.contains(PixelPoint(x: 3, y: 0)) && round.contains(PixelPoint(x: 0, y: 3)))
        for p in round {
            XCTAssertTrue(round.contains(PixelPoint(x: 9 - p.x, y: p.y)) && round.contains(PixelPoint(x: p.x, y: 9 - p.y)), "symmetric at \(p)")
        }
        let outline = Set(Raster.rectangle(from: a, to: b, filled: false, radius: 3))
        XCTAssertTrue(outline.isSubset(of: round))
        XCTAssertFalse(outline.contains(PixelPoint(x: 5, y: 5)))
        XCTAssertEqual(Set(Raster.rectangle(from: a, to: PixelPoint(x: 2, y: 9), filled: true, radius: 20)).count,
                       Set(Raster.rectangle(from: a, to: PixelPoint(x: 2, y: 9), filled: true, radius: 1)).count, "the radius is clamped")
    }
}

@MainActor
final class ShapeToolDocumentTests: XCTestCase {
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 16, height: 16, background: nil, palette: []))
        doc.primary = .black
        return doc
    }

    private func pixel(_ doc: SpriteDocument, _ x: Int, _ y: Int) -> PixelColor {
        doc.sprite.cel(layer: doc.activeLayerID, frame: doc.activeFrame.id)?[x, y] ?? .clear
    }

    private func drag(_ doc: SpriteDocument, _ a: PixelPoint, _ b: PixelPoint) {
        doc.beginStroke(at: a)
        doc.continueStroke(to: b)
        doc.endStroke()
    }

    func testCurveIsBentInTwoMoreDragsAndIsOneUndoStep() {
        let doc = makeDocument()
        doc.select(.curve)
        drag(doc, PixelPoint(x: 0, y: 15), PixelPoint(x: 15, y: 15))
        XCTAssertEqual(doc.pendingShapeStage, 2)
        XCTAssertEqual(pixel(doc, 8, 15), .black, "the straight line is previewed")
        XCTAssertFalse(doc.canUndo, "not committed yet")
        drag(doc, PixelPoint(x: 7, y: 0), PixelPoint(x: 8, y: 0))
        XCTAssertEqual(doc.pendingShapeStage, 3)
        XCTAssertEqual(pixel(doc, 8, 15), .clear, "the line bends up")
        XCTAssertEqual(doc.shapeGuides.handles.count, 4)
        drag(doc, PixelPoint(x: 15, y: 0), PixelPoint(x: 15, y: 0))
        XCTAssertFalse(doc.isBuildingShape)
        XCTAssertEqual(pixel(doc, 0, 15), .black)
        XCTAssertEqual(pixel(doc, 15, 15), .black)
        doc.undo()
        XCTAssertNil(doc.sprite.cel(layer: doc.activeLayerID, frame: doc.activeFrame.id))
        XCTAssertFalse(doc.canUndo)
    }

    func testChangingToolKeepsAPendingCurveAndUndoCancelsIt() {
        let doc = makeDocument()
        doc.select(.curve)
        drag(doc, PixelPoint(x: 0, y: 0), PixelPoint(x: 9, y: 0))
        doc.select(.pencil)
        XCTAssertFalse(doc.isBuildingShape)
        XCTAssertEqual(pixel(doc, 5, 0), .black)
        XCTAssertTrue(doc.canUndo)

        doc.select(.curve)
        drag(doc, PixelPoint(x: 0, y: 5), PixelPoint(x: 9, y: 5))
        doc.undo()
        XCTAssertFalse(doc.isBuildingShape)
        XCTAssertEqual(pixel(doc, 5, 5), .clear, "undo drops the curve in progress")
        XCTAssertEqual(pixel(doc, 5, 0), .black, "and nothing else")
    }

    func testCancelledBendKeepsTheCurve() {
        let doc = makeDocument()
        doc.select(.curve)
        drag(doc, PixelPoint(x: 0, y: 8), PixelPoint(x: 15, y: 8))
        doc.beginStroke(at: PixelPoint(x: 8, y: 0))
        doc.cancelStroke()
        XCTAssertEqual(doc.pendingShapeStage, 2)
        XCTAssertEqual(pixel(doc, 8, 8), .black, "back to the straight line")
    }

    func testPolygonClosesOnTheFirstCorner() {
        let doc = makeDocument()
        doc.select(.polygon)
        for p in [PixelPoint(x: 1, y: 1), PixelPoint(x: 10, y: 1), PixelPoint(x: 10, y: 10), PixelPoint(x: 1, y: 10)] {
            doc.beginStroke(at: p)
            doc.endStroke()
        }
        XCTAssertTrue(doc.isBuildingShape)
        XCTAssertEqual(doc.shapeGuides.handles.count, 4)
        doc.beginStroke(at: PixelPoint(x: 1, y: 1))
        doc.endStroke()
        XCTAssertFalse(doc.isBuildingShape)
        XCTAssertEqual(pixel(doc, 5, 5), .black, "filled")
        XCTAssertEqual(pixel(doc, 12, 12), .clear)
        doc.undo()
        XCTAssertEqual(pixel(doc, 5, 5), .clear, "one undo step")
    }

    func testPolygonDoneButton() {
        let doc = makeDocument()
        doc.select(.polygon)
        for p in [PixelPoint(x: 0, y: 0), PixelPoint(x: 8, y: 0), PixelPoint(x: 0, y: 8)] {
            drag(doc, p, p)
        }
        doc.finishPendingShape()
        XCTAssertEqual(pixel(doc, 2, 2), .black)
        XCTAssertEqual(pixel(doc, 7, 7), .clear)
    }

    func testContourFillsWhatYouDraw() {
        let doc = makeDocument()
        doc.select(.contour)
        doc.beginStroke(at: PixelPoint(x: 2, y: 2))
        doc.continueStroke(through: [PixelPoint(x: 12, y: 2), PixelPoint(x: 12, y: 12), PixelPoint(x: 2, y: 12)])
        XCTAssertEqual(pixel(doc, 7, 7), .clear, "only the outline while drawing")
        doc.endStroke()
        XCTAssertEqual(pixel(doc, 7, 7), .black)
        XCTAssertEqual(pixel(doc, 13, 13), .clear)
    }

    func testRectangleCornerRadius() {
        let doc = makeDocument()
        doc.select(.rectangle)
        doc.cornerRadius = 3
        drag(doc, PixelPoint(x: 0, y: 0), PixelPoint(x: 9, y: 9))
        XCTAssertEqual(pixel(doc, 0, 0), .clear)
        XCTAssertEqual(pixel(doc, 5, 0), .black)
    }
}
