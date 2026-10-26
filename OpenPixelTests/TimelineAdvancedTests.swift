import XCTest
@testable import OpenPixel

@MainActor
final class TimelineAdvancedTests: XCTestCase {
    /// 4 frames on 2 layers; frame n of the top layer has pixel (n, 0).
    private func makeDocument(width: Int = 4) -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: width, height: 4, background: nil, palette: []))
        doc.primary = .black
        doc.addLayer()
        for n in 0..<4 {
            if n > 0 { doc.addFrame(empty: true) }
            doc.beginStroke(at: PixelPoint(x: n, y: 0))
            doc.endStroke()
        }
        return doc
    }

    private func marker(_ doc: SpriteDocument, frame: Int, layer: Int? = nil) -> Int? {
        let image: PixelImage
        if let layer {
            let s = doc.sprite
            guard let cel = s.cel(layer: s.layers[layer].id, frame: s.frames[frame].id) else { return nil }
            image = cel
        } else {
            image = doc.sprite.composite(frameIndex: frame)
        }
        return (0..<4).first { image[$0, 0] == .black }
    }

    private var top: Int { 1 }

    // MARK: Pick cels

    func testCelsPickedAcrossLayersAllEndUpInTheBlock() {
        let doc = makeDocument()
        doc.addLayer()
        let ids = doc.sprite.layers.map(\.id)
        // Bottom layer, up through the others, and back down to the bottom.
        doc.extendRange(layer: ids[0], frameIndex: 0)
        doc.extendRange(layer: ids[1], frameIndex: 1)
        doc.extendRange(layer: ids[2], frameIndex: 2)
        doc.extendRange(layer: ids[0], frameIndex: 3)
        XCTAssertEqual(doc.timelineRange?.layers, Set(ids))
        XCTAssertEqual(doc.timelineRange?.frames, 0...3)
        // A tap inside trims the block back to the anchor.
        doc.extendRange(layer: ids[1], frameIndex: 1)
        XCTAssertEqual(doc.timelineRange?.layers, Set(ids[0...1]))
        XCTAssertEqual(doc.timelineRange?.frames, 0...1)
    }

    func testPickedCelsStayTheScopeOfAFillAfterDone() {
        let doc = makeDocument()
        let ids = doc.sprite.layers.map(\.id)
        // The bottom layer gets a pixel at (3, 3) in frame 2.
        doc.selectCel(layer: ids[0], frameIndex: 2)
        doc.beginStroke(at: PixelPoint(x: 3, y: 3))
        doc.endStroke()
        doc.isSelectingRange = true
        doc.extendRange(layer: ids[1], frameIndex: 1)
        doc.extendRange(layer: ids[0], frameIndex: 2)
        doc.isSelectingRange = false
        doc.selectCel(layer: ids[1], frameIndex: 1)
        doc.selectAll()
        doc.primary = .white
        doc.fillSelection()
        let s = doc.sprite
        XCTAssertEqual(s.cel(layer: ids[1], frame: s.frames[2].id)?[2, 0], .white, "another frame's cel is recolored")
        XCTAssertEqual(s.cel(layer: ids[0], frame: s.frames[2].id)?[3, 3], .white, "another layer's cel is recolored")
        XCTAssertEqual(s.cel(layer: ids[1], frame: s.frames[1].id)?[0, 3], .white, "the active cel takes the empty part")
        XCTAssertEqual(s.cel(layer: ids[1], frame: s.frames[0].id)?[0, 0], .black, "cels outside the block stay")
    }

    // MARK: Move and copy cels

    func testMoveCelsPastTheEndAddsFrames() {
        let doc = makeDocument()
        let topID = doc.sprite.layers[top].id
        doc.extendRange(layer: topID, frameIndex: 2)
        doc.extendRange(layer: topID, frameIndex: 3)
        doc.dropRange(from: (topID, 2), to: (topID, 4))
        XCTAssertEqual(doc.sprite.frames.count, 6)
        XCTAssertEqual((0..<6).map { marker(doc, frame: $0, layer: top) }, [0, 1, nil, nil, 2, 3])
        XCTAssertEqual(doc.timelineRange?.frames, 4...5, "the selection follows the block")
        doc.undo()
        XCTAssertEqual(doc.sprite.frames.count, 4)
        XCTAssertEqual((0..<4).map { marker(doc, frame: $0, layer: top) }, [0, 1, 2, 3])
    }

    func testMoveCelsToAnotherLayerReplacesWhatIsThere() {
        let doc = makeDocument()
        let s = doc.sprite
        doc.extendRange(layer: s.layers[top].id, frameIndex: 1)
        doc.dropRange(from: (s.layers[top].id, 1), to: (s.layers[0].id, 3))
        XCTAssertNil(marker(doc, frame: 1, layer: top))
        XCTAssertEqual(marker(doc, frame: 3, layer: 0), 1)
        XCTAssertEqual(marker(doc, frame: 3, layer: top), 3)
    }

    func testBlockCannotLeaveTheLayerStack() {
        var sprite = makeDocument().sprite
        let applied = sprite.moveCels(layerIndices: [1], frameRange: 0...0, dLayers: 3, dFrames: 0, copy: false)
        XCTAssertEqual(applied.dLayers, 0)
        XCTAssertEqual(applied.dFrames, 0)
    }

    func testCopyCelsOnContinuousLayerLinksThem() {
        let doc = makeDocument()
        let topID = doc.sprite.layers[top].id
        doc.toggleContinuous(topID)
        doc.dragCopies = true
        doc.extendRange(layer: topID, frameIndex: 0)
        doc.dropRange(from: (topID, 0), to: (topID, 2))
        XCTAssertEqual(marker(doc, frame: 0, layer: top), 0, "copying keeps the original")
        XCTAssertEqual(marker(doc, frame: 2, layer: top), 0)
        let key = { CelKey(layer: topID, frame: doc.sprite.frames[$0].id) }
        XCTAssertEqual(doc.sprite.links[key(0)], doc.sprite.links[key(2)])
        XCTAssertNotNil(doc.sprite.links[key(0)])
    }

    func testCopyCelsOnRegularLayerDoesNotLink() {
        let doc = makeDocument()
        let topID = doc.sprite.layers[top].id
        doc.dragCopies = true
        doc.extendRange(layer: topID, frameIndex: 0)
        doc.dropRange(from: (topID, 0), to: (topID, 2))
        XCTAssertEqual(marker(doc, frame: 2, layer: top), 0)
        XCTAssertTrue(doc.sprite.links.isEmpty)
    }

    // MARK: Move and copy frames

    func testMoveFramesBlock() {
        let doc = makeDocument()
        doc.extendRange(frameIndex: 0)
        doc.extendRange(frameIndex: 1)
        doc.dropRange(from: (doc.sprite.layers[top].id, 0), to: (doc.sprite.layers[top].id, 3))
        XCTAssertEqual((0..<4).map { marker(doc, frame: $0) }, [2, 3, 0, 1])
        XCTAssertEqual(doc.timelineRange?.frames, 2...3)
        XCTAssertEqual(doc.timelineRange?.kind, .frames)
    }

    func testDroppingFramesOnThemselvesDoesNothing() {
        let doc = makeDocument()
        doc.extendRange(frameIndex: 1)
        doc.extendRange(frameIndex: 2)
        doc.dropRange(from: (doc.sprite.layers[top].id, 1), to: (doc.sprite.layers[top].id, 2))
        XCTAssertEqual((0..<4).map { marker(doc, frame: $0) }, [0, 1, 2, 3])
        XCTAssertFalse(doc.canRedo)
    }

    func testCopyFramesPastTheEnd() {
        let doc = makeDocument()
        doc.dragCopies = true
        doc.extendRange(frameIndex: 0)
        doc.extendRange(frameIndex: 1)
        doc.dropRange(from: (doc.sprite.layers[top].id, 0), to: (doc.sprite.layers[top].id, 4))
        XCTAssertEqual((0..<6).map { marker(doc, frame: $0) }, [0, 1, 2, 3, 0, 1])
    }

    // MARK: Layers

    func testMoveAndCopyLayers() {
        let doc = makeDocument()
        doc.addLayer()
        let ids = doc.sprite.layers.map(\.id)
        doc.isSelectingRange = true
        doc.extendRange(layerRow: ids[0])
        XCTAssertEqual(doc.timelineRange?.kind, .layers)
        doc.dropRange(from: (ids[0], 0), to: (ids[2], 0))
        XCTAssertEqual(doc.sprite.layers.map(\.id), [ids[1], ids[2], ids[0]])

        doc.dragCopies = true
        doc.dropRange(from: (ids[0], 0), to: (ids[1], 0))
        XCTAssertEqual(doc.sprite.layers.count, 4)
        XCTAssertEqual(doc.sprite.layers[1].name, L10n.string("%@ copy", doc.sprite.layers[3].name))
    }

    func testDuplicateLayerKeepsCelsAndLinksSeparately() {
        let doc = makeDocument()
        let topID = doc.sprite.layers[top].id
        doc.extendRange(layer: topID, frameIndex: 0)
        doc.extendRange(layer: topID, frameIndex: 1)
        doc.linkRange()
        doc.endRangeSelection()
        doc.duplicateLayer(topID)
        let copy = doc.sprite.layers[2]
        XCTAssertEqual(doc.activeLayerID, copy.id)
        XCTAssertEqual(marker(doc, frame: 3, layer: 2), 3)
        let k = { CelKey(layer: $0, frame: doc.sprite.frames[$1].id) }
        XCTAssertEqual(doc.sprite.links[k(copy.id, 0)], doc.sprite.links[k(copy.id, 1)])
        XCTAssertNotEqual(doc.sprite.links[k(copy.id, 0)], doc.sprite.links[k(topID, 0)], "the copy's links are its own")
    }

    func testDeleteRangeLayersKeepsOne() {
        let doc = makeDocument()
        doc.extendRange(layerRow: doc.sprite.layers[0].id)
        doc.extendRange(layerRow: doc.sprite.layers[1].id)
        doc.deleteRangeLayers()
        XCTAssertEqual(doc.sprite.layers.count, 2)
        XCTAssertNotNil(doc.notice)
        doc.extendRange(layerRow: doc.sprite.layers[0].id)
        doc.deleteRangeLayers()
        XCTAssertEqual(doc.sprite.layers.count, 1)
        XCTAssertTrue(doc.sprite.cels.keys.allSatisfy { $0.layer == doc.sprite.layers[0].id })
    }

    // MARK: Copy between documents

    func testCopyFramesIntoAnotherDocumentOfAnotherSize() {
        let source = makeDocument()
        source.extendRange(frameIndex: 2)
        source.extendRange(frameIndex: 3)
        source.copyRange()

        // Cels go to layers by position, so the target needs a second layer.
        let target = SpriteDocument(name: "Other", sprite: .blank(width: 3, height: 2, background: nil, palette: []))
        target.addLayer()
        target.pasteFrames()
        XCTAssertEqual(target.sprite.frames.count, 3)
        let pasted = target.sprite.composite(frameIndex: 1)
        XCTAssertEqual(pasted.width, 3)
        XCTAssertEqual(pasted[2, 0], .black, "frame 2's pixel (2, 0) fits")
        XCTAssertTrue(target.sprite.composite(frameIndex: 2).isEmpty, "frame 3's pixel (3, 0) is cut")
    }

    func testCopyAndPasteCels() {
        let doc = makeDocument()
        let s = doc.sprite
        doc.extendRange(layer: s.layers[top].id, frameIndex: 0)
        doc.extendRange(layer: s.layers[top].id, frameIndex: 1)
        doc.copyRange()
        doc.endRangeSelection()
        doc.selectCel(layer: s.layers[0].id, frameIndex: 3)
        doc.pasteCels()
        XCTAssertEqual(doc.sprite.frames.count, 5)
        XCTAssertEqual(marker(doc, frame: 3, layer: 0), 0)
        XCTAssertEqual(marker(doc, frame: 4, layer: 0), 1)
    }

    func testCopyAndPasteLayers() {
        let doc = makeDocument()
        doc.extendRange(layerRow: doc.sprite.layers[top].id)
        doc.copyRange()
        doc.endRangeSelection()
        doc.pasteLayers()
        XCTAssertEqual(doc.sprite.layers.count, 3)
        XCTAssertEqual((0..<4).map { marker(doc, frame: $0, layer: 2) }, [0, 1, 2, 3])
        XCTAssertNotEqual(doc.sprite.layers[2].id, doc.sprite.layers[1].id)
    }

    // MARK: Tags, loop and focus

    func testTagAndLoopSectionUseTheSelectedFrames() {
        let doc = makeDocument()
        doc.extendRange(frameIndex: 1)
        doc.extendRange(frameIndex: 2)
        let tag = doc.addTag()
        XCTAssertEqual(tag.from...tag.to, 1...2)
        doc.setLoopSection()
        doc.endRangeSelection()
        doc.goToFrame(3)
        doc.setLoopSection()
        let loops = doc.sprite.tags.filter { $0.name == SpriteDocument.loopTagName }
        XCTAssertEqual(loops.count, 1, "the loop section is reused")
        XCTAssertEqual(loops.first.map { $0.from...$0.to }, 3...3)
    }

    func testFocusedBandPlaysOnlyItsTags() {
        var sprite = makeDocument().sprite
        sprite.tags = [
            FrameTag(name: "all", from: 0, to: 3, color: .black),
            FrameTag(name: "a", from: 0, to: 1, color: .black),
            FrameTag(name: "b", from: 2, to: 3, color: .black),
        ]
        XCTAssertEqual(sprite.tagBandCount, 2)
        XCTAssertEqual(sprite.playbackCycle(at: 2).frames, [2, 3], "innermost tag by default")
        // Band 0 holds "a" and "b"; "all" overlaps them and goes to band 1.
        XCTAssertEqual(sprite.playbackCycle(at: 2, band: 0).frames, [2, 3])
        XCTAssertEqual(sprite.playbackCycle(at: 2, band: 1).frames, [0, 1, 2, 3])
        XCTAssertEqual(sprite.playbackCycle(at: 0, band: 0).frames, [0, 1])
    }

    func testRangeDuration() {
        let doc = makeDocument()
        doc.extendRange(frameIndex: 1)
        doc.extendRange(frameIndex: 2)
        doc.setRangeDuration(250)
        XCTAssertEqual(doc.sprite.frames.map(\.duration), [100, 250, 250, 100])
    }

    func testUsualFrameDurationFindsTheOddOnesOut() {
        var sprite = makeDocument().sprite
        XCTAssertNil(sprite.usualFrameDuration, "all frames last the same: nothing to mark")
        sprite.frames[2].duration = 4000
        XCTAssertEqual(sprite.usualFrameDuration, 100)
        sprite.frames[0].duration = 4000
        sprite.frames[1].duration = 4000
        XCTAssertEqual(sprite.usualFrameDuration, 4000, "the most common duration wins")
        sprite.frames[1].duration = 100
        XCTAssertEqual(sprite.usualFrameDuration, 4000, "a tie goes to the first frame's duration")
    }

    func testLongFrameDurations() {
        let doc = makeDocument()
        doc.setDuration(4000, frameIndex: 1)
        XCTAssertEqual(doc.sprite.frames[1].duration, 4000, "a frame can hold for 4 seconds")
        doc.setDuration(1_000_000, frameIndex: 1)
        XCTAssertEqual(doc.sprite.frames[1].duration, SpriteDocument.maxFrameDuration)
        XCTAssertEqual(doc.sprite.totalDuration, 300 + SpriteDocument.maxFrameDuration)
    }

    // MARK: Cel opacity

    func testCelOpacityBlendsAndIsSharedByLinkedCels() throws {
        let doc = makeDocument()
        let topID = doc.sprite.layers[top].id
        doc.extendRange(layer: topID, frameIndex: 0)
        doc.extendRange(layer: topID, frameIndex: 1)
        doc.linkRange()
        doc.endRangeSelection()
        doc.setCelOpacity(0.5, layer: topID, frameIndex: 1)
        XCTAssertEqual(doc.celOpacity(layer: topID, frameIndex: 0), 0.5)
        XCTAssertEqual(doc.sprite.composite(frameIndex: 0)[0, 0].a, 128)
        XCTAssertEqual(doc.sprite.composite(frameIndex: 2)[2, 0].a, 255)

        let decoded = try JSONDecoder().decode(Sprite.self, from: JSONEncoder().encode(doc.sprite))
        XCTAssertEqual(decoded, doc.sprite)

        doc.clearRange()
        doc.extendRange(layer: topID, frameIndex: 0)
        doc.clearRange()
        XCTAssertNil(doc.sprite.celOpacity[CelKey(layer: topID, frame: doc.sprite.frames[0].id)], "empty cels drop their opacity")
    }

    // MARK: Background layer and header toggles

    private func makeBackgroundDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Bg", sprite: .blank(width: 4, height: 4, background: .white, palette: []))
        doc.primary = .black
        doc.secondary = PixelColor(r: 255, g: 0, b: 0, a: 255)
        return doc
    }

    func testNewOpaqueSpriteHasABackgroundThatErasesToSecondary() {
        let doc = makeBackgroundDocument()
        XCTAssertTrue(doc.sprite.layers[0].isBackground)
        doc.select(.eraser)
        doc.beginStroke(at: PixelPoint(x: 1, y: 1))
        doc.endStroke()
        XCTAssertEqual(doc.sprite.composite(frameIndex: 0)[1, 1], doc.secondary)
        doc.selectAll()
        doc.deleteSelection()
        XCTAssertEqual(doc.sprite.composite(frameIndex: 0)[3, 3], doc.secondary, "clearing leaves the secondary color")
    }

    func testBackgroundStaysAtTheBottom() {
        let doc = makeBackgroundDocument()
        let bg = doc.sprite.layers[0].id
        doc.addLayer()
        let top = doc.sprite.layers[1].id
        doc.moveLayer(bg, by: 1)
        doc.moveLayer(top, to: bg)
        XCTAssertEqual(doc.sprite.layers.map(\.id), [bg, top])
        XCTAssertFalse(doc.canRedo)
        doc.setOpacity(0.5, layer: bg)
        XCTAssertEqual(doc.sprite.layers[0].opacity, 1)
    }

    func testConvertBetweenLayerAndBackground() {
        let doc = makeBackgroundDocument()
        let bg = doc.sprite.layers[0].id
        doc.addLayer()
        let layer = doc.sprite.layers[1].id
        doc.convertToBackground(layer)
        XCTAssertNotNil(doc.notice, "only one background")
        doc.convertToLayer(bg)
        XCTAssertFalse(doc.sprite.layers[0].isBackground)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.endStroke()
        doc.addFrame(empty: true)
        doc.convertToBackground(layer)
        XCTAssertEqual(doc.sprite.layers.map(\.id), [layer, bg], "the new background goes to the bottom")
        let frames = doc.sprite.frames
        XCTAssertEqual(doc.sprite.cel(layer: layer, frame: frames[0].id)?[0, 0], .black)
        XCTAssertEqual(doc.sprite.cel(layer: layer, frame: frames[0].id)?[2, 2], doc.secondary, "transparent pixels take the secondary color")
        XCTAssertEqual(doc.sprite.cel(layer: layer, frame: frames[1].id)?[0, 0], doc.secondary, "empty frames get a cel")
    }

    func testHeaderTogglesActOnEveryLayer() {
        let doc = makeDocument()
        doc.toggleVisibility(doc.sprite.layers[0].id)
        doc.toggleAllVisibility()
        XCTAssertTrue(doc.sprite.layers.allSatisfy(\.isVisible), "some hidden: show all")
        doc.toggleAllVisibility()
        XCTAssertTrue(doc.sprite.layers.allSatisfy { !$0.isVisible })
        doc.toggleAllLocks()
        XCTAssertTrue(doc.sprite.layers.allSatisfy(\.isLocked))
        doc.toggleAllContinuous()
        XCTAssertTrue(doc.sprite.layers.allSatisfy(\.isContinuous))
    }
}
