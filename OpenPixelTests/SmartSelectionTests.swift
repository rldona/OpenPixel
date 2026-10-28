import XCTest
@testable import OpenPixel

@MainActor
final class SmartSelectionTests: XCTestCase {
    /// Bottom layer: a 2×1 bar at (1, 1)–(2, 1). Top layer: a dot at (5, 5).
    /// With All layers on, unless `allLayers` is false, and Fit to content on.
    private func makeDocument(allLayers: Bool = true) -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 8, background: nil, palette: []))
        doc.primary = .black
        for x in 1...2 { doc.beginStroke(at: PixelPoint(x: x, y: 1)); doc.endStroke() }
        doc.addLayer()
        doc.beginStroke(at: PixelPoint(x: 5, y: 5)); doc.endStroke()
        doc.select(.selectRectangle)
        doc.selectionAllLayers = allLayers
        doc.selectionFitsContent = true
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

    func testATapPicksWithinTheTimelineRange() {
        let doc = makeDocument(allLayers: false)
        doc.isSelectingRange = true
        doc.extendRange(layerRow: doc.sprite.layers[0].id)
        doc.extendRange(layerRow: doc.sprite.layers[1].id)
        tap(doc, 1, 1)
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 1, minY: 1, maxX: 2, maxY: 1), "the bar, from a layer in the range")
        XCTAssertNotNil(doc.timelineRange, "the range stays")
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

    func testByDefaultAMarqueeTakesOnlyTheActiveLayer() {
        let doc = makeDocument(allLayers: false)
        let bottom = doc.sprite.layers[0].id, top = doc.sprite.layers[1].id
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 7, y: 7))
        doc.endStroke()
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 5, minY: 5, maxX: 5, maxY: 5), "only the dot, on the active layer")
        XCTAssertNil(doc.timelineRange)
        doc.beginTransformDrag(.move, at: CGPoint(x: 5.5, y: 5.5))
        doc.continueTransformDrag(to: CGPoint(x: 6.5, y: 6.5))
        doc.endTransformDrag()
        doc.applyTransform()
        let frame = doc.sprite.frames[0].id
        XCTAssertEqual(doc.sprite.cel(layer: bottom, frame: frame)?[1, 1], .black, "the other layer stays")
        XCTAssertEqual(doc.sprite.cel(layer: top, frame: frame)?[6, 6], .black)
    }

    func testMarqueeOverSeveralLayersTakesThemAll() {
        let doc = makeDocument()
        let bottom = doc.sprite.layers[0].id, top = doc.sprite.layers[1].id
        XCTAssertEqual(doc.activeLayerID, top)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 7, y: 7))
        doc.endStroke()
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 1, minY: 1, maxX: 5, maxY: 5), "the bar (bottom layer) and the dot (top layer)")
        XCTAssertEqual(doc.timelineRange?.layers, [bottom, top], "All layers marks them in the timeline")

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

    func testWithoutAllLayersAMarqueeStaysOnTheActiveLayer() {
        let doc = makeDocument(allLayers: false)
        doc.beginStroke(at: PixelPoint(x: 4, y: 4))
        doc.continueStroke(to: PixelPoint(x: 6, y: 6))
        doc.endStroke()
        XCTAssertNil(doc.timelineRange)
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

    /// As in Aseprite: Copy takes the active layer, Copy merged every visible one.
    func testCopyTakesTheActiveLayerAndCopyMergedTakesThemAll() throws {
        let doc = makeDocument()
        selectEverything(doc)
        doc.copy(merged: true)
        let (merged, origin) = try XCTUnwrap(PixelClipboard.read(maxSize: 64))
        XCTAssertEqual(origin, PixelPoint(x: 1, y: 1))
        XCTAssertEqual(merged.width, 5)
        XCTAssertEqual(merged[0, 0], .black, "the bar")
        XCTAssertEqual(merged[4, 4], .black, "the dot")
        doc.cut()
        let (image, _) = try XCTUnwrap(PixelClipboard.read(maxSize: 64))
        XCTAssertEqual(image[0, 0], .clear, "not the bar")
        XCTAssertEqual(image[4, 4], .black, "only the active layer's dot")
        XCTAssertEqual(pixel(doc, layer: 0, 1, 1), .black, "cut leaves the other layer alone")
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
        XCTAssertEqual(doc.transformExtraCels, 3, "every other cel of the range")
        doc.continueTransformDrag(to: CGPoint(x: 1.5, y: 3.5))
        doc.applyTransform()
        XCTAssertEqual(pixel(doc, layer: 0, frame: 1, 1, 3), .black)
        XCTAssertEqual(pixel(doc, layer: 1, frame: 1, 5, 5), .black, "the other layer stays")
    }

    // MARK: Locked layers

    func testLockedLayersDontWidenOrMove() {
        let doc = makeDocument()
        let bottom = doc.sprite.layers[0].id
        doc.toggleLock(bottom)
        doc.select(.selectRectangle)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 7, y: 7))
        doc.endStroke()
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 5, minY: 5, maxX: 5, maxY: 5), "only the unlocked dot")
        tap(doc, 1, 1)
        XCTAssertNil(doc.selection, "a locked layer's element can't be picked")
        doc.selectionAllFrames = true
        doc.selectAll()
        doc.select(.move)
        doc.beginTransformDrag(.move, at: CGPoint(x: 5.5, y: 5.5))
        doc.continueTransformDrag(to: CGPoint(x: 6.5, y: 5.5))
        doc.applyTransform()
        XCTAssertEqual(pixel(doc, layer: 0, 1, 1), .black, "the locked bar stays put")
    }
}

/// The selection behaving as in Aseprite, across layers, frames and the timeline.
@MainActor
final class SelectionScopeTests: XCTestCase {
    /// Bottom layer: a 2×1 bar at (1, 1)–(2, 1). Top layer (active): a dot at (5, 5).
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 8, background: nil, palette: []))
        doc.primary = .black
        for x in 1...2 { doc.beginStroke(at: PixelPoint(x: x, y: 1)); doc.endStroke() }
        doc.addLayer()
        doc.beginStroke(at: PixelPoint(x: 5, y: 5)); doc.endStroke()
        doc.select(.selectRectangle)
        return doc
    }

    private func drag(_ doc: SpriteDocument, _ a: (Int, Int), _ b: (Int, Int)) {
        doc.beginStroke(at: PixelPoint(x: a.0, y: a.1))
        doc.continueStroke(to: PixelPoint(x: b.0, y: b.1))
        doc.endStroke()
    }

    private func move(_ doc: SpriteDocument, dx: Double) {
        doc.beginTransformDrag(.move, at: CGPoint(x: 1, y: 1))
        doc.continueTransformDrag(to: CGPoint(x: 1 + dx, y: 1))
        doc.endTransformDrag()
    }

    private func drawn(_ doc: SpriteDocument, layer: Int, frame: Int = 0, _ x: Int, _ y: Int) -> Bool {
        let key = CelKey(layer: doc.sprite.layers[layer].id, frame: doc.sprite.frames[frame].id)
        return (doc.sprite.cels[key]?[PixelPoint(x: x, y: y)].a ?? 0) != 0
    }

    func testFitToContentIsOffSoTheShapeCanBePaintedIn() {
        let doc = makeDocument()
        doc.selectCel(layer: doc.sprite.layers[0].id, frameIndex: 0)
        drag(doc, (0, 0), (4, 4))
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 0, minY: 0, maxX: 4, maxY: 4), "the rectangle you drew")
        doc.select(.pencil)
        doc.beginStroke(at: PixelPoint(x: 3, y: 3)); doc.endStroke()
        XCTAssertTrue(drawn(doc, layer: 0, 3, 3), "its empty part can be painted")
    }

    func testSubtractingTakesTheWholeShapeEvenWithFitOn() {
        let doc = makeDocument()
        doc.selectionFitsContent = true
        doc.selectCel(layer: doc.sprite.layers[0].id, frameIndex: 0)
        doc.selectAll()
        doc.selectionMode = .subtract
        drag(doc, (0, 0), (3, 3))
        XCTAssertFalse(doc.selection!.contains(PixelPoint(x: 0, y: 0)), "empty pixels go too")
        XCTAssertFalse(doc.selection!.contains(PixelPoint(x: 1, y: 1)))
        XCTAssertTrue(doc.selection!.contains(PixelPoint(x: 5, y: 5)))
    }

    func testTheSelectionStaysAfterAMoveAndAcrossFrames() {
        let doc = makeDocument()
        doc.addFrame()
        doc.selectCel(layer: doc.sprite.layers[0].id, frameIndex: 0)
        drag(doc, (0, 0), (2, 2))
        move(doc, dx: 2)
        doc.activeFrameIndex = 1
        XCTAssertFalse(doc.isTransforming, "changing frames drops the pixels")
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 2, minY: 0, maxX: 4, maxY: 2), "and the selection stays where they went")
        XCTAssertTrue(doc.dragMovesSelection(at: PixelPoint(x: 3, y: 1)), "ready to move the next frame the same way")
        move(doc, dx: -2)
        doc.applyTransform()
        XCTAssertTrue(drawn(doc, layer: 0, frame: 0, 3, 1), "frame 1 moved right")
        XCTAssertTrue(drawn(doc, layer: 0, frame: 1, 0, 1), "frame 2 moved left")
        XCTAssertNotNil(doc.selection)
    }

    func testLockedAndHiddenLayersCanBeCopiedButNotCut() {
        let doc = makeDocument()
        let bottom = doc.sprite.layers[0].id
        doc.selectCel(layer: bottom, frameIndex: 0)
        doc.toggleLock(bottom)
        doc.selectAll()
        XCTAssertTrue(doc.copy(), "locking stops edits, not copying")
        XCTAssertEqual(PixelClipboard.read(maxSize: 64)?.0[1, 1], .black)
        doc.cut()
        XCTAssertTrue(drawn(doc, layer: 0, 1, 1), "cut leaves a locked layer alone")
        doc.toggleLock(bottom)
        doc.toggleVisibility(bottom)
        XCTAssertTrue(doc.copy(), "a hidden layer copies too")
    }

    func testAGroupCheckedInTheTimelineStandsForItsLayers() {
        let doc = makeDocument()
        doc.groupLayers(doc.sprite.layers.map(\.id))
        let group = doc.sprite.layers.first { $0.isGroup }!.id
        doc.toggleLayerCheck(group)
        doc.selectAll()
        doc.primary = .white
        doc.fillSelection()
        XCTAssertFalse(doc.sprite.cels.keys.contains { $0.layer == group }, "a group holds no pixels")
        XCTAssertEqual(doc.sprite.cel(layer: doc.sprite.layers[0].id, frame: doc.sprite.frames[0].id)?[1, 1], .white, "its layers recolor")
        XCTAssertEqual(doc.sprite.cel(layer: doc.sprite.layers[1].id, frame: doc.sprite.frames[0].id)?[5, 5], .white)
    }

    func testARangeLeavesHiddenLayersAloneWhenMoving() {
        let doc = makeDocument()
        doc.selectCel(layer: doc.sprite.layers[0].id, frameIndex: 0)
        doc.toggleVisibility(doc.sprite.layers[1].id)
        doc.isSelectingRange = true
        doc.extendRange(frameIndex: 0)
        doc.select(.move)
        move(doc, dx: 1)
        doc.applyTransform()
        XCTAssertTrue(drawn(doc, layer: 0, 3, 1), "the visible bar moves")
        XCTAssertTrue(drawn(doc, layer: 1, 5, 5), "the hidden dot stays, as with delete")
    }

    func testAllFramesMovesALayerInEveryFrameWithTheMoveTool() {
        let doc = makeDocument()
        doc.addFrame()
        doc.selectCel(layer: doc.sprite.layers[0].id, frameIndex: 0)
        doc.selectionAllFrames = true
        doc.select(.move)
        move(doc, dx: 1)
        doc.applyTransform()
        XCTAssertTrue(drawn(doc, layer: 0, frame: 1, 3, 1), "without a selection too")
        XCTAssertTrue(drawn(doc, layer: 1, frame: 1, 5, 5), "the other layer stays")
    }

    /// All layers and All frames are shortcuts for the timeline range, as in
    /// Aseprite, where the range is what edits change.
    func testTheTogglesMarkTheTimelineRangeAndFollowTheActiveCel() {
        let doc = makeDocument()
        doc.addFrame()
        doc.goToFrame(0)
        let all = Set(doc.sprite.layers.map(\.id))
        doc.selectionAllLayers = true
        XCTAssertEqual(doc.timelineRange, TimelineRange(kind: .cels, layers: all, frames: 0...0))
        doc.goToFrame(1)
        XCTAssertEqual(doc.timelineRange?.frames, 1...1, "it follows the frame")
        doc.selectionAllFrames = true
        XCTAssertEqual(doc.timelineRange?.frames, 0...1)
        doc.selectionAllLayers = false
        XCTAssertEqual(doc.timelineRange?.layers, [doc.activeLayerID])
        doc.selectCel(layer: doc.sprite.layers[0].id, frameIndex: 0)
        doc.focusTimeline(.cel)
        XCTAssertEqual(doc.timelineRange?.layers, [doc.sprite.layers[0].id], "it follows the layer, even after a timeline tap")
        doc.isSelectingRange = true
        XCTAssertFalse(doc.selectionAllFrames, "picking a range by hand turns them off")
        XCTAssertNil(doc.timelineRange)
        doc.endRangeSelection()
        XCTAssertNil(doc.timelineRange)
    }

    /// A tap selects the piece under it, on the active layer only.
    func testATapPicksThePieceOnTheActiveLayer() {
        let doc = makeDocument()
        let top = doc.activeLayerID
        doc.select(.pencil)
        doc.beginStroke(at: PixelPoint(x: 1, y: 6)); doc.endStroke()
        doc.select(.selectRectangle)
        doc.beginStroke(at: PixelPoint(x: 5, y: 5)); doc.endStroke()
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 5, minY: 5, maxX: 5, maxY: 5), "the dot, not the other piece of its layer")
        doc.beginStroke(at: PixelPoint(x: 1, y: 1)); doc.endStroke()
        XCTAssertNil(doc.selection, "the bar is on another layer: the tap deselects")
        XCTAssertEqual(doc.activeLayerID, top, "and the layer stays")
    }

    func testALockedActiveLayerDoesNotStopTheOthersFromMoving() {
        let doc = makeDocument()
        doc.selectionAllLayers = true
        drag(doc, (0, 0), (6, 6))
        doc.toggleLock(doc.activeLayerID)
        move(doc, dx: 1)
        doc.applyTransform()
        XCTAssertTrue(drawn(doc, layer: 0, 3, 1), "the unlocked bar moves")
        XCTAssertTrue(drawn(doc, layer: 1, 5, 5), "the locked dot stays")
    }
}
