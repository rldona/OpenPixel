import XCTest
@testable import OpenPixel

@MainActor
final class SmartSelectionTests: XCTestCase {
    /// Bottom layer: a 2×1 bar at (1, 1)–(2, 1). Top layer: a dot at (5, 5).
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 8, background: nil, palette: []))
        doc.primary = .black
        for x in 1...2 { doc.beginStroke(at: PixelPoint(x: x, y: 1)); doc.endStroke() }
        doc.addLayer()
        doc.beginStroke(at: PixelPoint(x: 5, y: 5)); doc.endStroke()
        doc.select(.selectRectangle)
        return doc
    }

    private func tap(_ doc: SpriteDocument, _ x: Int, _ y: Int) {
        doc.beginStroke(at: PixelPoint(x: x, y: y))
        doc.endStroke()
    }

    func testTapSelectsTheElementAndItsLayer() {
        let doc = makeDocument()
        let bottom = doc.sprite.layers[0].id
        tap(doc, 2, 1)
        XCTAssertEqual(doc.activeLayerID, bottom, "the layer under the finger becomes active")
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 1, minY: 1, maxX: 2, maxY: 1), "exactly its pixels")
        XCTAssertFalse(doc.selection!.contains(PixelPoint(x: 5, y: 5)))
        tap(doc, 6, 6)
        XCTAssertNil(doc.selection, "tapping empty canvas deselects")
        doc.undo()
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 1, minY: 1, maxX: 2, maxY: 1))
    }

    func testAddModeCollectsElementsAndHiddenLayersAreSkipped() {
        let doc = makeDocument()
        tap(doc, 1, 1)
        doc.selectionMode = .add
        tap(doc, 5, 5)
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 1, minY: 1, maxX: 5, maxY: 5))
        doc.selectionMode = .replace
        doc.toggleVisibility(doc.sprite.layers[1].id)
        tap(doc, 5, 5)
        XCTAssertNil(doc.selection, "a hidden layer can't be picked")
    }

    func testTapEndsTheTimelineRange() {
        let doc = makeDocument()
        doc.isSelectingRange = true
        doc.extendRange(layerRow: doc.sprite.layers[0].id)
        doc.extendRange(layerRow: doc.sprite.layers[1].id)
        tap(doc, 5, 5)
        XCTAssertNil(doc.timelineRange, "picking one element leaves the multi-layer range")
    }

    func testMarqueeFitsTheDrawnPixels() {
        let doc = makeDocument()
        doc.selectCel(layer: doc.sprite.layers[0].id, frameIndex: 0)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 4, y: 4))
        doc.endStroke()
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 1, minY: 1, maxX: 2, maxY: 1), "only the bar, not the empty rectangle")
    }

    func testMarqueeOverEmptyCanvasOrWithFitOffKeepsTheShape() {
        let doc = makeDocument()
        doc.beginStroke(at: PixelPoint(x: 0, y: 4))
        doc.continueStroke(to: PixelPoint(x: 2, y: 6))
        doc.endStroke()
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 0, minY: 4, maxX: 2, maxY: 6), "nothing drawn there: keep the rectangle")

        doc.selectionFitsContent = false
        doc.selectCel(layer: doc.sprite.layers[0].id, frameIndex: 0)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 4, y: 4))
        doc.endStroke()
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 0, minY: 0, maxX: 4, maxY: 4))
    }

    func testMarqueeFitsEveryLayerOfTheRange() {
        let doc = makeDocument()
        doc.isSelectingRange = true
        doc.extendRange(layerRow: doc.sprite.layers[0].id)
        doc.extendRange(layerRow: doc.sprite.layers[1].id)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 7, y: 7))
        doc.endStroke()
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 1, minY: 1, maxX: 5, maxY: 5), "the bar and the dot, from both layers")
        XCTAssertNotNil(doc.timelineRange, "dragging keeps the range")
    }

    func testMarqueeOverSeveralLayersTakesThemAll() {
        let doc = makeDocument()
        let bottom = doc.sprite.layers[0].id, top = doc.sprite.layers[1].id
        XCTAssertEqual(doc.activeLayerID, top)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 7, y: 7))
        doc.endStroke()
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 1, minY: 1, maxX: 5, maxY: 5), "the bar (bottom layer) and the dot (top layer)")
        XCTAssertEqual(doc.selectionLayers, [bottom, top])

        doc.beginTransformDrag(.move, at: CGPoint(x: 5.5, y: 5.5))
        XCTAssertEqual(doc.transformExtraCels, 1)
        doc.continueTransformDrag(to: CGPoint(x: 6.5, y: 6.5))
        doc.endTransformDrag()
        doc.applyTransform()
        let frame = doc.sprite.frames[0].id
        XCTAssertEqual(doc.sprite.cel(layer: bottom, frame: frame)?[2, 2], .black, "the bar moved with the dot")
        XCTAssertEqual(doc.sprite.cel(layer: bottom, frame: frame)?[1, 1], .clear)
        XCTAssertEqual(doc.sprite.cel(layer: top, frame: frame)?[6, 6], .black)
        doc.undo()
        XCTAssertEqual(doc.sprite.cel(layer: bottom, frame: frame)?[1, 1], .black, "one undo step for both layers")
    }

    func testMarqueeOverOneLayerStaysOnThatLayer() {
        let doc = makeDocument()
        doc.beginStroke(at: PixelPoint(x: 4, y: 4))
        doc.continueStroke(to: PixelPoint(x: 6, y: 6))
        doc.endStroke()
        XCTAssertNil(doc.selectionLayers)
        doc.select(.move)
        doc.beginTransformDrag(.move, at: CGPoint(x: 5.5, y: 5.5))
        XCTAssertEqual(doc.transformExtraCels, 0)
        doc.cancelTransform()
    }

    // MARK: Editing a multi-layer selection

    private func selectEverything(_ doc: SpriteDocument) {
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 7, y: 7))
        doc.endStroke()
    }

    private func pixel(_ doc: SpriteDocument, layer: Int, _ x: Int, _ y: Int) -> PixelColor {
        doc.sprite.cel(layer: doc.sprite.layers[layer].id, frame: doc.sprite.frames[0].id)?[x, y] ?? .clear
    }

    func testDeleteClearsEveryLayerOfTheSelection() {
        let doc = makeDocument()
        selectEverything(doc)
        doc.deleteSelection()
        XCTAssertEqual(pixel(doc, layer: 0, 1, 1), .clear)
        XCTAssertEqual(pixel(doc, layer: 1, 5, 5), .clear)
        doc.undo()
        XCTAssertEqual(pixel(doc, layer: 0, 1, 1), .black)
        XCTAssertEqual(pixel(doc, layer: 1, 5, 5), .black)
    }

    func testFillRecolorsEachLayerInPlace() {
        let doc = makeDocument()
        selectEverything(doc)
        let red = PixelColor(r: 255, g: 0, b: 0)
        doc.primary = red
        doc.fillSelection()
        XCTAssertEqual(pixel(doc, layer: 0, 1, 1), red, "the bar stays on its layer")
        XCTAssertEqual(pixel(doc, layer: 1, 5, 5), red)
        XCTAssertEqual(pixel(doc, layer: 1, 1, 1), .clear, "the top layer doesn't get a copy of the bar")
    }

    func testCopyMergesTheLayersAndCutClearsThem() throws {
        let doc = makeDocument()
        selectEverything(doc)
        doc.cut()
        let (image, origin) = try XCTUnwrap(PixelClipboard.read(maxSize: 64))
        XCTAssertEqual(origin, PixelPoint(x: 1, y: 1))
        XCTAssertEqual(image.width, 5)
        XCTAssertEqual(image[0, 0], .black, "the bar")
        XCTAssertEqual(image[4, 4], .black, "the dot")
        XCTAssertEqual(pixel(doc, layer: 0, 1, 1), .clear)
        XCTAssertEqual(pixel(doc, layer: 1, 5, 5), .clear)
    }

    func testLockedLayersAreLeftAlone() {
        let doc = makeDocument()
        selectEverything(doc)
        doc.toggleLock(doc.sprite.layers[0].id)
        doc.deleteSelection()
        XCTAssertEqual(pixel(doc, layer: 0, 1, 1), .black)
        XCTAssertEqual(pixel(doc, layer: 1, 5, 5), .clear)
    }

    // MARK: Every frame

    /// The same sprite with a second frame copied from the first.
    private func makeTwoFrameDocument() -> SpriteDocument {
        let doc = makeDocument()
        doc.addFrame()
        doc.goToFrame(0)
        return doc
    }

    private func pixel(_ doc: SpriteDocument, layer: Int, frame: Int, _ x: Int, _ y: Int) -> PixelColor {
        doc.sprite.cel(layer: doc.sprite.layers[layer].id, frame: doc.sprite.frames[frame].id)?[x, y] ?? .clear
    }

    func testMoveInEveryFrame() {
        let doc = makeTwoFrameDocument()
        doc.selectionAllFrames = true
        selectEverything(doc)
        doc.beginTransformDrag(.move, at: CGPoint(x: 5.5, y: 5.5))
        XCTAssertEqual(doc.transformExtraCels, 3, "the other layer, and both layers of frame 2")
        doc.continueTransformDrag(to: CGPoint(x: 6.5, y: 5.5))
        doc.endTransformDrag()
        doc.applyTransform()
        for frame in 0..<2 {
            XCTAssertEqual(pixel(doc, layer: 0, frame: frame, 2, 1), .black, "frame \(frame)")
            XCTAssertEqual(pixel(doc, layer: 0, frame: frame, 1, 1), .clear, "frame \(frame)")
            XCTAssertEqual(pixel(doc, layer: 1, frame: frame, 6, 5), .black, "frame \(frame)")
        }
    }

    func testDeleteInEveryFrameOnlyWhenAsked() {
        let doc = makeTwoFrameDocument()
        selectEverything(doc)
        doc.deleteSelection()
        XCTAssertEqual(pixel(doc, layer: 0, frame: 1, 1, 1), .black, "off: other frames untouched")
        doc.undo()
        doc.selectionAllFrames = true
        doc.deleteSelection()
        XCTAssertEqual(pixel(doc, layer: 0, frame: 1, 1, 1), .clear)
        XCTAssertEqual(pixel(doc, layer: 1, frame: 1, 5, 5), .clear)
    }

    func testTappedElementMovesInEveryFrame() {
        let doc = makeTwoFrameDocument()
        doc.selectionAllFrames = true
        tap(doc, 1, 1)
        doc.beginTransformDrag(.move, at: CGPoint(x: 1.5, y: 1.5))
        XCTAssertEqual(doc.transformExtraCels, 1, "the bar in frame 2")
        doc.continueTransformDrag(to: CGPoint(x: 1.5, y: 3.5))
        doc.applyTransform()
        XCTAssertEqual(pixel(doc, layer: 0, frame: 1, 1, 3), .black)
        XCTAssertEqual(pixel(doc, layer: 1, frame: 1, 5, 5), .black, "the other layer stays")
    }
}
