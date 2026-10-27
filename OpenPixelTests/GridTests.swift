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

/// Snap to grid with the drawing tools, as in Aseprite: points go to the
/// closest grid corner, offset so the brush's top-left pixel lands on it.
@MainActor
final class SnapToGridToolTests: XCTestCase {
    private func makeDocument(_ tool: Tool) -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 32, height: 32, background: nil, palette: []))
        doc.setGrid(GridSettings(width: 8, height: 8))
        doc.snapToGrid = true
        doc.primary = .black
        doc.select(tool)
        return doc
    }

    private func painted(_ doc: SpriteDocument) -> Set<PixelPoint> {
        guard let cel = doc.sprite.cel(layer: doc.sprite.layers[0].id, frame: doc.sprite.frames[0].id) else { return [] }
        var points = Set<PixelPoint>()
        for y in 0..<cel.height { for x in 0..<cel.width where cel[x, y].a != 0 { points.insert(PixelPoint(x: x, y: y)) } }
        return points
    }

    func testThePencilDrawsFreelyInsideTheCells() {
        let doc = makeDocument(.pencil)
        doc.beginStroke(at: PixelPoint(x: 3, y: 2))
        doc.continueStroke(to: PixelPoint(x: 5, y: 2))
        doc.endStroke()
        XCTAssertEqual(painted(doc), [PixelPoint(x: 3, y: 2), PixelPoint(x: 4, y: 2), PixelPoint(x: 5, y: 2)])
    }

    func testABrushAsBigAsACellFillsWholeCells() {
        let doc = makeDocument(.pencil)
        doc.setBrushSize(8)
        doc.beginStroke(at: PixelPoint(x: 10, y: 11))
        doc.endStroke()
        let expected = Set((8..<16).flatMap { y in (8..<16).map { PixelPoint(x: $0, y: y) } })
        XCTAssertEqual(painted(doc), expected, "exactly the cell from (8, 8) to (15, 15)")
    }

    func testRectanglesCoverWholeCells() {
        let doc = makeDocument(.rectangle)
        doc.shapeFilled = true
        doc.beginStroke(at: PixelPoint(x: 1, y: 1))
        doc.continueStroke(to: PixelPoint(x: 15, y: 9))
        doc.endStroke()
        let points = painted(doc)
        XCTAssertEqual(points.map(\.x).min(), 0)
        XCTAssertEqual(points.map(\.x).max(), 15)
        XCTAssertEqual(points.map(\.y).min(), 0)
        XCTAssertEqual(points.map(\.y).max(), 7)
    }

    func testLinesGoFromCornerToCorner() {
        let doc = makeDocument(.line)
        doc.beginStroke(at: PixelPoint(x: 1, y: 1))
        doc.continueStroke(to: PixelPoint(x: 17, y: 2))
        doc.endStroke()
        let points = painted(doc)
        XCTAssertEqual(points, Set((0...16).map { PixelPoint(x: $0, y: 0) }))
    }

    func testWithoutSnapNothingMoves() {
        let doc = makeDocument(.pencil)
        doc.snapToGrid = false
        doc.beginStroke(at: PixelPoint(x: 3, y: 2))
        doc.endStroke()
        XCTAssertEqual(painted(doc), [PixelPoint(x: 3, y: 2)])
    }
}

@MainActor
final class SnapToGridSliceTests: XCTestCase {
    func testNewSlicesTakeWholeCells() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 32, height: 32, background: nil, palette: []))
        doc.setGrid(GridSettings(width: 8, height: 8))
        doc.snapToGrid = true
        doc.select(.slice)
        doc.beginStroke(at: PixelPoint(x: 3, y: 3))
        doc.continueStroke(to: PixelPoint(x: 12, y: 5))
        doc.endStroke()
        let bounds = doc.sprite.slices.first?.keys.first?.bounds
        XCTAssertEqual(bounds, PixelRect(minX: 0, minY: 0, maxX: 15, maxY: 7))
    }
}

@MainActor
final class CanvasSizeTests: XCTestCase {
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 16, height: 16, background: nil, palette: []))
        doc.primary = .black
        doc.select(.pencil)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.endStroke()
        return doc
    }

    private func pixel(_ doc: SpriteDocument, _ x: Int, _ y: Int) -> PixelColor {
        doc.sprite.cel(layer: doc.sprite.layers[0].id, frame: doc.sprite.frames[0].id)?[x, y] ?? .clear
    }

    func testAnchoredLeftGrowsToTheRight() {
        let doc = makeDocument()
        doc.resizeCanvas(width: 48, height: 16, anchor: (0, 1))
        XCTAssertEqual(doc.sprite.width, 48)
        XCTAssertEqual(pixel(doc, 0, 0), .black, "the drawing stays on the left")
        doc.undo()
        XCTAssertEqual(doc.sprite.width, 16, "one undo step")
    }

    func testAnchoredRightGrowsToTheLeft() {
        let doc = makeDocument()
        doc.resizeCanvas(width: 48, height: 16, anchor: (2, 1))
        XCTAssertEqual(pixel(doc, 32, 0), .black, "the drawing moves 32 px right")
        XCTAssertEqual(pixel(doc, 0, 0), .clear)
    }

    func testCenteredGrowsBothWaysAndSlicesFollow() {
        let doc = makeDocument()
        doc.select(.slice)
        doc.beginStroke(at: PixelPoint(x: 2, y: 2))
        doc.continueStroke(to: PixelPoint(x: 5, y: 5))
        doc.endStroke()
        doc.resizeCanvas(width: 32, height: 32, anchor: (1, 1))
        XCTAssertEqual(pixel(doc, 8, 8), .black)
        XCTAssertEqual(doc.sprite.slices.first?.keys.first?.bounds, PixelRect(minX: 10, minY: 10, maxX: 13, maxY: 13))
    }

    func testShrinkingCrops() {
        let doc = makeDocument()
        doc.resizeCanvas(width: 8, height: 8, anchor: (2, 2))
        XCTAssertEqual(doc.sprite.width, 8)
        XCTAssertEqual(pixel(doc, 0, 0), .clear, "the corner pixel was cut off")
        XCTAssertNil(doc.sprite.cel(layer: doc.sprite.layers[0].id, frame: doc.sprite.frames[0].id))
    }
}

@MainActor
final class CanvasResizeDragTests: XCTestCase {
    func testDraggingTheRightEdgeGrowsToTheRightOnApply() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 32, height: 32, background: nil, palette: []))
        doc.primary = .black
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.endStroke()
        doc.beginCanvasResize()
        let start = doc.canvasResize!
        doc.dragCanvasEdges(.right, from: start, by: (dx: 16.4, dy: 3))
        XCTAssertEqual(doc.canvasResize, PixelRect(minX: 0, minY: 0, maxX: 47, maxY: 31), "only the right side moves")
        XCTAssertEqual(doc.sprite.width, 32, "nothing changes before Apply")
        doc.applyCanvasResize()
        XCTAssertEqual(doc.sprite.width, 48)
        XCTAssertNil(doc.canvasResize)
        XCTAssertEqual(doc.sprite.cel(layer: doc.sprite.layers[0].id, frame: doc.sprite.frames[0].id)?[0, 0], .black)
        doc.undo()
        XCTAssertEqual(doc.sprite.width, 32)
    }

    func testTheLeftEdgeGrowsToTheLeftAndCellsSnap() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 32, height: 32, background: nil, palette: []))
        doc.setGrid(GridSettings(width: 16, height: 16))
        doc.canvasResizeInCells = true
        defer { doc.canvasResizeInCells = false }
        doc.beginCanvasResize()
        doc.dragCanvasEdges(.left, from: doc.canvasResize!, by: (dx: -11, dy: 0))
        XCTAssertEqual(doc.canvasResize?.minX, -16, "snapped to a whole cell")
        doc.applyCanvasResize()
        XCTAssertEqual(doc.sprite.width, 48)
    }

    func testCancelLeavesTheCanvas() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 32, height: 32, background: nil, palette: []))
        doc.beginCanvasResize()
        doc.dragCanvasEdges([.right, .bottom], from: doc.canvasResize!, by: (dx: 10, dy: 10))
        doc.cancelCanvasResize()
        XCTAssertEqual(doc.sprite.width, 32)
        XCTAssertFalse(doc.canUndo)
    }
}
