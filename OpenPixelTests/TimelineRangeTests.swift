import XCTest
@testable import OpenPixel

@MainActor
final class LinkedCelTests: XCTestCase {
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        doc.primary = .black
        return doc
    }

    private func pixel(_ doc: SpriteDocument, frame: Int, _ x: Int, _ y: Int) -> PixelColor {
        doc.sprite.composite(frameIndex: frame)[x, y]
    }

    private func draw(_ doc: SpriteDocument, _ x: Int, _ y: Int) {
        doc.select(.pencil)
        doc.beginStroke(at: PixelPoint(x: x, y: y))
        doc.endStroke()
    }

    func testContinuousLayerLinksNewFramesAndEditsPropagate() {
        let doc = makeDocument()
        doc.toggleContinuous(doc.activeLayerID)
        draw(doc, 0, 0)
        doc.addFrame()
        doc.addFrame()
        XCTAssertEqual(doc.sprite.links.count, 3)
        draw(doc, 3, 3)
        for frame in 0..<3 {
            XCTAssertEqual(pixel(doc, frame: frame, 3, 3), .black, "frame \(frame) didn't get the edit")
        }
        doc.undo()
        for frame in 0..<3 { XCTAssertEqual(pixel(doc, frame: frame, 3, 3), .clear) }
    }

    func testRegularLayerCopiesInsteadOfLinking() {
        let doc = makeDocument()
        draw(doc, 0, 0)
        doc.addFrame()
        draw(doc, 1, 1)
        XCTAssertTrue(doc.sprite.links.isEmpty)
        XCTAssertEqual(pixel(doc, frame: 0, 1, 1), .clear)
    }

    func testUnlinkStopsPropagation() {
        let doc = makeDocument()
        doc.toggleContinuous(doc.activeLayerID)
        draw(doc, 0, 0)
        doc.addFrame()
        doc.unlinkCel(layer: doc.activeLayerID, frameIndex: 1)
        XCTAssertTrue(doc.sprite.links.isEmpty, "a one-cel group is dropped")
        draw(doc, 2, 2)
        XCTAssertEqual(pixel(doc, frame: 0, 2, 2), .clear)
        XCTAssertEqual(pixel(doc, frame: 1, 0, 0), .black, "unlinking keeps a copy of the image")
    }

    func testDeletingAFrameKeepsTheRestLinked() {
        let doc = makeDocument()
        doc.toggleContinuous(doc.activeLayerID)
        draw(doc, 0, 0)
        doc.addFrame()
        doc.addFrame()
        doc.deleteFrame(at: 1)
        XCTAssertEqual(doc.sprite.links.count, 2)
        doc.deleteFrame(at: 1)
        XCTAssertTrue(doc.sprite.links.isEmpty)
    }

    func testTransformOnLinkedCelPropagates() {
        let doc = makeDocument()
        doc.toggleContinuous(doc.activeLayerID)
        draw(doc, 0, 0)
        doc.addFrame()
        doc.beginTransform()
        doc.nudgeTransform(dx: 2, dy: 0)
        doc.applyTransform()
        XCTAssertEqual(pixel(doc, frame: 0, 2, 0), .black)
        XCTAssertEqual(pixel(doc, frame: 0, 0, 0), .clear)
    }

    func testLinksSurviveCodableAndOldFilesDecode() throws {
        var sprite = Sprite.blank(width: 2, height: 2, background: .white, palette: [])
        sprite.layers[0].isContinuous = true
        sprite.frames.append(Frame())
        sprite.link(sprite.frames.map { CelKey(layer: sprite.layers[0].id, frame: $0.id) })
        let decoded = try JSONDecoder().decode(Sprite.self, from: JSONEncoder().encode(sprite))
        XCTAssertEqual(decoded, sprite)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(sprite)) as? [String: Any])
        json.removeValue(forKey: "links")
        var layers = try XCTUnwrap(json["layers"] as? [[String: Any]])
        layers[0].removeValue(forKey: "isContinuous")
        json["layers"] = layers
        let legacy = try JSONDecoder().decode(Sprite.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(legacy.links.isEmpty)
        XCTAssertFalse(legacy.layers[0].isContinuous)
    }
}

@MainActor
final class TimelineRangeTests: XCTestCase {
    /// 4 frames on 2 layers; frame n of the top layer has pixel (n, 0).
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        doc.primary = .black
        doc.addLayer()
        for n in 0..<4 {
            if n > 0 { doc.addFrame(empty: true) }
            doc.beginStroke(at: PixelPoint(x: n, y: 0))
            doc.endStroke()
        }
        return doc
    }

    private func marker(_ doc: SpriteDocument, frame: Int) -> Int? {
        let image = doc.sprite.composite(frameIndex: frame)
        return (0..<4).first { image[$0, 0] == .black }
    }

    func testExtendRangeBuildsABlock() {
        let doc = makeDocument()
        let bottom = doc.sprite.layers[0].id, top = doc.sprite.layers[1].id
        doc.isSelectingRange = true
        doc.extendRange(layer: top, frameIndex: 1)
        doc.extendRange(layer: bottom, frameIndex: 3)
        XCTAssertEqual(doc.timelineRange, TimelineRange(layers: [top, bottom], frames: 1...3))
        doc.endRangeSelection()
        XCTAssertNil(doc.timelineRange)
        XCTAssertFalse(doc.isSelectingRange)
    }

    func testReverseFrames() {
        let doc = makeDocument()
        doc.extendRange(frameIndex: 0)
        doc.extendRange(frameIndex: 3)
        doc.reverseRangeFrames()
        XCTAssertEqual((0..<4).map { marker(doc, frame: $0) }, [3, 2, 1, 0])
        doc.undo()
        XCTAssertEqual((0..<4).map { marker(doc, frame: $0) }, [0, 1, 2, 3])
    }

    func testDuplicateAndDeleteFrames() {
        let doc = makeDocument()
        doc.extendRange(frameIndex: 1)
        doc.extendRange(frameIndex: 2)
        doc.duplicateRangeFrames()
        XCTAssertEqual((0..<6).map { marker(doc, frame: $0) }, [0, 1, 2, 1, 2, 3])
        XCTAssertEqual(doc.timelineRange?.frames, 3...4, "the copies become the selection")
        doc.deleteRangeFrames()
        XCTAssertEqual((0..<4).map { marker(doc, frame: $0) }, [0, 1, 2, 3])
    }

    func testCannotDeleteEveryFrame() {
        let doc = makeDocument()
        doc.extendRange(frameIndex: 0)
        doc.extendRange(frameIndex: 3)
        doc.deleteRangeFrames()
        XCTAssertEqual(doc.sprite.frames.count, 4)
        XCTAssertNotNil(doc.notice)
    }

    func testLinkAndClearRange() {
        let doc = makeDocument()
        let top = doc.activeLayerID
        doc.extendRange(layer: top, frameIndex: 0)
        doc.extendRange(layer: top, frameIndex: 2)
        doc.linkRange()
        XCTAssertEqual((0..<4).map { marker(doc, frame: $0) }, [0, 0, 0, 3], "linked cels take the first frame's image")
        doc.goToFrame(1)
        doc.beginStroke(at: PixelPoint(x: 3, y: 3))
        doc.endStroke()
        XCTAssertEqual(doc.sprite.composite(frameIndex: 2)[3, 3], .black)
        doc.clearRange()
        XCTAssertTrue(doc.sprite.links.isEmpty)
        XCTAssertNil(marker(doc, frame: 0))
        XCTAssertEqual(marker(doc, frame: 3), 3)
    }
}

@MainActor
final class LayerCheckTests: XCTestCase {
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        doc.addLayer()
        doc.addLayer()
        doc.addFrame(empty: true)
        return doc
    }

    func testChecksBuildALayerSelection() {
        let doc = makeDocument()
        let ids = doc.sprite.layers.map(\.id)
        doc.toggleLayerCheck(ids[0])
        doc.toggleLayerCheck(ids[2])
        XCTAssertTrue(doc.isSelectingRange)
        XCTAssertEqual(doc.timelineRange?.kind, .layers)
        XCTAssertEqual(doc.checkedLayers, [ids[0], ids[2]], "layers needn't be next to each other")
        XCTAssertEqual(doc.timelineRange?.frames, 0...1, "every frame")
        doc.toggleLayerCheck(ids[0])
        XCTAssertEqual(doc.checkedLayers, [ids[2]])
        doc.toggleLayerCheck(ids[2])
        XCTAssertNil(doc.timelineRange, "unchecking the last one ends the selection")
        XCTAssertFalse(doc.isSelectingRange)
    }

    func testHeaderChecksAllThenNone() {
        let doc = makeDocument()
        doc.toggleAllLayerChecks()
        XCTAssertEqual(doc.checkedLayers, Set(doc.sprite.layers.map(\.id)))
        doc.toggleAllLayerChecks()
        XCTAssertNil(doc.timelineRange)
    }

    func testACelSelectionIsReplacedByChecks() {
        let doc = makeDocument()
        let ids = doc.sprite.layers.map(\.id)
        doc.isSelectingRange = true
        doc.extendRange(layer: ids[1], frameIndex: 0)
        XCTAssertEqual(doc.checkedLayers, [], "cels aren't checked layers")
        doc.toggleLayerCheck(ids[0])
        XCTAssertEqual(doc.checkedLayers, [ids[0]])
    }

    func testCheckedLayersCanBeDeleted() {
        let doc = makeDocument()
        let ids = doc.sprite.layers.map(\.id)
        doc.toggleLayerCheck(ids[1])
        doc.toggleLayerCheck(ids[2])
        doc.deleteRangeLayers()
        XCTAssertEqual(doc.sprite.layers.map(\.id), [ids[0]])
    }
}
