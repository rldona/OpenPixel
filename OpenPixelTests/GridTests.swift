import XCTest
@testable import OpenPixel

final class GridModelTests: XCTestCase {
    func testCellsAndSnapping() {
        let grid = GridSettings(width: 8, height: 4, offsetX: 2, offsetY: 0)
        XCTAssertEqual(grid.cell(containing: PixelPoint(x: 3, y: 5)), PixelRect(minX: 2, minY: 4, maxX: 9, maxY: 7))
        XCTAssertEqual(grid.cell(containing: PixelPoint(x: 1, y: 0)), PixelRect(minX: -6, minY: 0, maxX: 1, maxY: 3), "left of the offset")
        XCTAssertEqual(grid.cells(from: PixelPoint(x: 3, y: 1), to: PixelPoint(x: 11, y: 2)), PixelRect(minX: 2, minY: 0, maxX: 17, maxY: 3))
        let (dx, dy) = grid.snap(dx: 5, dy: -1)
        XCTAssertEqual(dx, 8)
        XCTAssertEqual(dy, 0)
    }
}

@MainActor
final class GridDocumentTests: XCTestCase {
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 16, height: 16, background: nil, palette: []))
        doc.primary = .black
        doc.setGrid(GridSettings(width: 8, height: 8))
        return doc
    }

    func testGridIsSavedAndUndoable() throws {
        let doc = makeDocument()
        XCTAssertEqual(doc.sprite.grid.width, 8)
        doc.undo()
        XCTAssertEqual(doc.sprite.grid.width, 16)
        doc.redo()
        let decoded = try JSONDecoder().decode(Sprite.self, from: JSONEncoder().encode(doc.sprite))
        XCTAssertEqual(decoded.grid, doc.sprite.grid)
        doc.setGrid(GridSettings(width: 0, height: 99))
        XCTAssertEqual(doc.sprite.grid.width, 1)
        XCTAssertEqual(doc.sprite.grid.height, 16, "clamped to the sprite")
    }

    func testMarqueeSnapsToCells() {
        let doc = makeDocument()
        doc.snapToGrid = true
        doc.selectionFitsContent = false
        doc.select(.selectRectangle)
        doc.beginStroke(at: PixelPoint(x: 2, y: 2))
        doc.continueStroke(to: PixelPoint(x: 9, y: 3))
        doc.endStroke()
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 0, minY: 0, maxX: 15, maxY: 7))
    }

    func testMoveGoesCellByCell() {
        let doc = makeDocument()
        doc.beginStroke(at: PixelPoint(x: 1, y: 1))
        doc.endStroke()
        doc.snapToGrid = true
        doc.select(.move)
        doc.beginTransformDrag(.move, at: CGPoint(x: 1, y: 1))
        doc.continueTransformDrag(to: CGPoint(x: 6, y: 2))
        doc.endTransformDrag()
        doc.applyTransform()
        XCTAssertEqual(doc.sprite.cel(layer: doc.activeLayerID, frame: doc.activeFrame.id)?[9, 1], .black, "5 px rounds to one 8 px cell")
    }

    func testBucketStopsAtGrid() {
        let doc = makeDocument()
        doc.fillStopsAtGrid = true
        doc.select(.bucket)
        doc.beginStroke(at: PixelPoint(x: 2, y: 2))
        doc.endStroke()
        let cel = doc.sprite.cel(layer: doc.activeLayerID, frame: doc.activeFrame.id)
        XCTAssertEqual(cel?[7, 7], .black)
        XCTAssertNil(cel.map { $0[8, 8] }.flatMap { $0 == .black ? $0 : nil }, "the next cell is left alone")
    }
}
