import XCTest
@testable import OpenPixel

@MainActor
final class MoveSelectionTests: XCTestCase {
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 8, background: nil, palette: []))
        doc.primary = .black
        return doc
    }

    private func dot(_ doc: SpriteDocument, _ x: Int, _ y: Int) {
        let tool = doc.tool
        doc.select(.pencil)
        doc.beginStroke(at: PixelPoint(x: x, y: y))
        doc.endStroke()
        doc.select(tool)
    }

    private func select(_ doc: SpriteDocument, from a: PixelPoint, to b: PixelPoint) {
        doc.select(.selectRectangle)
        doc.beginStroke(at: a)
        doc.continueStroke(to: b)
        doc.endStroke()
    }

    private func pixel(_ doc: SpriteDocument, layer: Int = 0, frame: Int = 0, _ x: Int, _ y: Int) -> PixelColor {
        let s = doc.sprite
        return s.cel(layer: s.layers[layer].id, frame: s.frames[frame].id)?[x, y] ?? .clear
    }

    // MARK: Drag inside the selection

    func testDragInsideTheSelectionMovesItsPixels() {
        let doc = makeDocument()
        dot(doc, 1, 1)
        select(doc, from: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 2, y: 2))
        XCTAssertEqual(doc.tool, .selectRectangle)
        XCTAssertTrue(doc.dragMovesSelection(at: PixelPoint(x: 1, y: 1)))
        XCTAssertFalse(doc.dragMovesSelection(at: PixelPoint(x: 6, y: 6)), "outside: select again")

        doc.beginTransformDrag(.move, at: CGPoint(x: 1.5, y: 1.5))
        doc.continueTransformDrag(to: CGPoint(x: 4.5, y: 3.5))
        doc.endTransformDrag()
        doc.applyTransform()
        XCTAssertEqual(pixel(doc, 1, 1), .clear)
        XCTAssertEqual(pixel(doc, 4, 3), .black)
        XCTAssertEqual(doc.tool, .selectRectangle, "the selection tool stays")
        XCTAssertTrue(doc.dragMovesSelection(at: PixelPoint(x: 4, y: 3)), "the selection stays where the pixels were dropped")
        XCTAssertFalse(doc.dragMovesSelection(at: PixelPoint(x: 0, y: 0)))
        doc.undo()
        XCTAssertEqual(pixel(doc, 1, 1), .black)
        XCTAssertTrue(doc.dragMovesSelection(at: PixelPoint(x: 1, y: 1)), "undo restores the pixels and the selection")
    }

    // MARK: Stretch (Ctrl+drag)

    /// A column, x = 3, rows 2–6: red head on top, black body.
    private func figure(_ doc: SpriteDocument) {
        for y in 3...6 { dot(doc, 3, y) }
        doc.primary = PixelColor(r: 255, g: 0, b: 0)
        dot(doc, 3, 2)
        doc.primary = .black
    }

    func testStretchMoveFillsTheGapWithTheTrailingEdge() {
        let doc = makeDocument()
        figure(doc)
        select(doc, from: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 7, y: 3))
        doc.beginTransformDrag(.move, at: CGPoint(x: 3.5, y: 2.5))
        doc.stretchMove = true
        doc.continueTransformDrag(to: CGPoint(x: 3.5, y: 0.5))
        doc.endTransformDrag()
        doc.applyTransform()
        XCTAssertEqual(pixel(doc, 3, 0), PixelColor(r: 255, g: 0, b: 0), "the head moved up")
        for y in 1...6 { XCTAssertEqual(pixel(doc, 3, y), .black, "row \(y) stays joined") }
        XCTAssertFalse(doc.stretchMove, "stretching lasts one transform")
        doc.undo()
        XCTAssertEqual(pixel(doc, 3, 2), PixelColor(r: 255, g: 0, b: 0))
        XCTAssertEqual(pixel(doc, 3, 0), .clear, "one undo step")
    }

    func testPlainMoveLeavesTheGap() {
        let doc = makeDocument()
        figure(doc)
        select(doc, from: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 7, y: 3))
        doc.beginTransformDrag(.move, at: CGPoint(x: 3.5, y: 2.5))
        doc.continueTransformDrag(to: CGPoint(x: 3.5, y: 0.5))
        doc.endTransformDrag()
        doc.applyTransform()
        XCTAssertEqual(pixel(doc, 3, 0), PixelColor(r: 255, g: 0, b: 0))
        XCTAssertEqual(pixel(doc, 3, 2), .clear)
        XCTAssertEqual(pixel(doc, 3, 3), .clear)
    }

    func testStretchGrowsTheSelectionOverTheStretch() {
        let doc = makeDocument()
        figure(doc)
        select(doc, from: PixelPoint(x: 3, y: 2), to: PixelPoint(x: 3, y: 3))
        doc.beginTransformDrag(.move, at: CGPoint(x: 3.5, y: 2.5))
        doc.stretchMove = true
        doc.continueTransformDrag(to: CGPoint(x: 6.5, y: 2.5))
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 3, minY: 2, maxX: 6, maxY: 3))
        XCTAssertEqual(doc.sprite.cel(layer: doc.sprite.layers[0].id, frame: doc.sprite.frames[0].id)?[4, 2], PixelColor(r: 255, g: 0, b: 0),
                       "sideways, the left edge stretches")
        doc.stretchMove = false
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 6, minY: 2, maxX: 6, maxY: 3), "turning it off tears the pixels away again")
        doc.cancelTransform()
    }

    func testOtherModesAndToolsStillSelect() {
        let doc = makeDocument()
        dot(doc, 1, 1)
        select(doc, from: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 2, y: 2))
        doc.selectionMode = .add
        XCTAssertFalse(doc.dragMovesSelection(at: PixelPoint(x: 1, y: 1)))
        doc.selectionMode = .replace
        doc.select(.magicWand)
        XCTAssertFalse(doc.dragMovesSelection(at: PixelPoint(x: 1, y: 1)))
        doc.select(.pencil)
        XCTAssertFalse(doc.dragMovesSelection(at: PixelPoint(x: 1, y: 1)))
    }

    // MARK: Timeline range

    /// Two layers × two frames, each cel with a dot at (1, 1).
    private func makeRangeDocument() -> SpriteDocument {
        let doc = makeDocument()
        doc.addLayer()
        doc.addFrame(empty: true)
        for layer in doc.sprite.layers {
            for frame in 0..<2 {
                doc.selectCel(layer: layer.id, frameIndex: frame)
                dot(doc, 1, 1)
            }
        }
        doc.selectCel(layer: doc.sprite.layers[1].id, frameIndex: 0)
        return doc
    }

    func testMoveToolMovesEveryCelOfTheRange() {
        let doc = makeRangeDocument()
        doc.isSelectingRange = true
        doc.extendRange(layerRow: doc.sprite.layers[0].id)
        doc.extendRange(layerRow: doc.sprite.layers[1].id)
        doc.select(.move)
        doc.beginTransformDrag(.move, at: CGPoint(x: 1.5, y: 1.5))
        XCTAssertEqual(doc.transformExtraCels, 3)
        doc.continueTransformDrag(to: CGPoint(x: 3.5, y: 2.5))
        doc.endTransformDrag()
        doc.applyTransform()
        for layer in 0..<2 {
            for frame in 0..<2 {
                XCTAssertEqual(pixel(doc, layer: layer, frame: frame, 1, 1), .clear, "layer \(layer) frame \(frame)")
                XCTAssertEqual(pixel(doc, layer: layer, frame: frame, 3, 2), .black, "layer \(layer) frame \(frame)")
            }
        }
        XCTAssertEqual(doc.transformExtraCels, 0)
        doc.undo()
        XCTAssertEqual(pixel(doc, layer: 0, frame: 1, 1, 1), .black, "one undo step for every cel")
    }

    func testWithoutARangeOnlyTheActiveCelMoves() {
        let doc = makeRangeDocument()
        doc.select(.move)
        doc.beginTransformDrag(.move, at: CGPoint(x: 1.5, y: 1.5))
        XCTAssertEqual(doc.transformExtraCels, 0)
        doc.continueTransformDrag(to: CGPoint(x: 3.5, y: 1.5))
        doc.applyTransform()
        XCTAssertEqual(pixel(doc, layer: 1, frame: 0, 3, 1), .black)
        XCTAssertEqual(pixel(doc, layer: 0, frame: 0, 1, 1), .black)
    }

    func testFlipAndLockedLayersInARange() {
        let doc = makeRangeDocument()
        doc.toggleLock(doc.sprite.layers[0].id)
        doc.isSelectingRange = true
        doc.extendRange(frameIndex: 0)
        doc.extendRange(frameIndex: 1)
        doc.flip(horizontal: true)
        XCTAssertEqual(doc.transformExtraCels, 1, "the locked layer's cels are left out")
        doc.applyTransform()
        XCTAssertEqual(pixel(doc, layer: 1, frame: 1, 6, 1), .black, "flipped across the whole canvas")
        XCTAssertEqual(pixel(doc, layer: 0, frame: 1, 1, 1), .black)
    }

    func testCancelLeavesTheRangeAlone() {
        let doc = makeRangeDocument()
        doc.isSelectingRange = true
        doc.extendRange(frameIndex: 0)
        doc.extendRange(frameIndex: 1)
        doc.select(.move)
        doc.beginTransformDrag(.move, at: CGPoint(x: 1.5, y: 1.5))
        doc.continueTransformDrag(to: CGPoint(x: 5.5, y: 5.5))
        doc.cancelTransform()
        XCTAssertEqual(pixel(doc, layer: 0, frame: 1, 1, 1), .black)
        XCTAssertEqual(doc.transformExtraCels, 0)
    }
}

@MainActor
final class SelectionOpacityTests: XCTestCase {
    private func cel(_ doc: SpriteDocument) -> PixelImage? {
        doc.sprite.cel(layer: doc.sprite.layers[0].id, frame: doc.sprite.frames[0].id)
    }

    func testTheSliderFadesOnlyTheSelectionAndUndoesInOneStep() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 8, background: nil, palette: []))
        doc.primary = PixelColor(r: 255, g: 0, b: 0)
        doc.select(.pencil)
        for x in 0..<4 { doc.beginStroke(at: PixelPoint(x: x, y: 0)); doc.endStroke() }
        doc.select(.selectRectangle)
        doc.selectionFitsContent = false
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 1, y: 1))
        doc.endStroke()
        XCTAssertEqual(doc.selectionOpacity, 1)

        doc.beginSelectionOpacity()
        doc.setSelectionOpacity(0.8)
        doc.setSelectionOpacity(0.5)
        doc.endSelectionOpacity()
        XCTAssertEqual(cel(doc)?[0, 0].a, 128, "half of 255")
        XCTAssertEqual(cel(doc)?[3, 0].a, 255, "outside the selection")
        XCTAssertEqual(doc.selectionOpacity, 0.5, "the slider stays where it was left")

        // A second drag works from the original pixels, not the faded ones.
        doc.beginSelectionOpacity()
        doc.setSelectionOpacity(1)
        doc.endSelectionOpacity()
        XCTAssertEqual(cel(doc)?[0, 0].a, 255)

        doc.undo()
        XCTAssertEqual(cel(doc)?[0, 0].a, 128, "each drag is one undo step")
        doc.undo()
        XCTAssertEqual(cel(doc)?[0, 0].a, 255)
        XCTAssertEqual(doc.selectionOpacity, 1)
    }
}
