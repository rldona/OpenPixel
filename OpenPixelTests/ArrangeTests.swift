import XCTest
@testable import OpenPixel

@MainActor
final class ArrangeTests: XCTestCase {
    /// Four layers, bottom to top: Layer 1…4, each with a pixel at (0, 0).
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        doc.primary = .black
        for n in 0..<4 {
            if n > 0 { doc.addLayer() }
            doc.beginStroke(at: PixelPoint(x: 0, y: 0))
            doc.endStroke()
        }
        return doc
    }

    private func names(_ doc: SpriteDocument) -> [String] { doc.sprite.layers.map(\.name) }

    func testForwardAndBackwardMoveOneStep() {
        let doc = makeDocument()
        let start = names(doc)
        doc.activeLayerID = doc.sprite.layers[1].id
        doc.arrange(.forward, everyFrame: true)
        XCTAssertEqual(names(doc), [start[0], start[2], start[1], start[3]])
        doc.arrange(.backward, everyFrame: true)
        doc.arrange(.backward, everyFrame: true)
        XCTAssertEqual(names(doc), [start[1], start[0], start[2], start[3]])
        XCTAssertFalse(doc.canArrange(forward: false, everyFrame: true), "already at the back")
    }

    func testFrontAndBackGoAllTheWay() {
        let doc = makeDocument()
        let start = names(doc)
        doc.activeLayerID = doc.sprite.layers[1].id
        doc.arrange(.front, everyFrame: true)
        XCTAssertEqual(names(doc).last, start[1])
        doc.arrange(.back, everyFrame: true)
        XCTAssertEqual(names(doc).first, start[1])
        doc.undo()
        XCTAssertEqual(names(doc).last, start[1], "each arrange is one undo step")
    }

    func testDuringATransformItJoinsTheTransformStep() {
        let doc = makeDocument()
        let start = names(doc)
        doc.activeLayerID = doc.sprite.layers[0].id
        doc.selectAll()
        doc.beginTransform()
        doc.arrange(.front, everyFrame: true)
        XCTAssertTrue(doc.isTransforming, "the transform stays open")
        XCTAssertEqual(names(doc).last, start[0])
        doc.cancelTransform()
        XCTAssertEqual(names(doc), start, "cancel puts the order back too")
        doc.beginTransform()
        doc.arrange(.front, everyFrame: true)
        doc.applyTransform()
        doc.undo()
        XCTAssertEqual(names(doc), start)
    }
}

@MainActor
final class CelZIndexTests: XCTestCase {
    /// Three layers, bottom to top, each filling (0, 0) with its own color, over two frames.
    private let colors = [PixelColor(r: 255, g: 0, b: 0), PixelColor(r: 0, g: 255, b: 0), PixelColor(r: 0, g: 0, b: 255)]

    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 2, height: 2, background: nil, palette: []))
        for (n, color) in colors.enumerated() {
            if n > 0 { doc.addLayer() }
            doc.primary = color
            doc.beginStroke(at: PixelPoint(x: 0, y: 0))
            doc.endStroke()
        }
        doc.addFrame(empty: false)
        return doc
    }

    private func top(_ doc: SpriteDocument, frame: Int) -> PixelColor {
        doc.sprite.composite(frameIndex: frame)[0, 0]
    }

    func testZIndexDrawsAboveTheLayersOverIt() {
        var sprite = makeDocument().sprite
        let key = CelKey(layer: sprite.layers[0].id, frame: sprite.frames[1].id)
        sprite.celZIndex[key] = 2
        XCTAssertEqual(sprite.composite(frameIndex: 1)[0, 0], colors[0], "+2 goes above the two layers over it")
        XCTAssertEqual(sprite.composite(frameIndex: 0)[0, 0], colors[2], "other frames don't change")
        sprite.celZIndex[key] = 1
        XCTAssertEqual(sprite.drawOrder(frame: sprite.frames[1].id).map(\.id), [sprite.layers[1].id, sprite.layers[0].id, sprite.layers[2].id])
    }

    func testBringToFrontInThisFrameOnly() {
        let doc = makeDocument()
        doc.activeLayerID = doc.sprite.layers[0].id
        doc.goToFrame(1)
        XCTAssertFalse(doc.canArrange(forward: false, everyFrame: false))
        doc.arrange(.front, everyFrame: false)
        XCTAssertEqual(top(doc, frame: 1), colors[0])
        XCTAssertEqual(top(doc, frame: 0), colors[2])
        XCTAssertEqual(doc.sprite.celZIndex.count, 1, "only that cel changes")
        XCTAssertFalse(doc.canArrange(forward: true, everyFrame: false))
        doc.arrange(.backward, everyFrame: false)
        XCTAssertEqual(top(doc, frame: 1), colors[2])
        doc.arrange(.back, everyFrame: false)
        XCTAssertTrue(doc.sprite.celZIndex.isEmpty, "back where it started")
        doc.undo()
        doc.undo()
        XCTAssertEqual(top(doc, frame: 1), colors[0])
    }

    func testSendToBackFromTheTop() {
        let doc = makeDocument()
        doc.activeLayerID = doc.sprite.layers[2].id
        doc.goToFrame(0)
        doc.arrange(.back, everyFrame: false)
        let order = doc.sprite.drawnCels(frame: doc.sprite.frames[0].id).map(\.layer)
        XCTAssertEqual(order, [doc.sprite.layers[2].id, doc.sprite.layers[0].id, doc.sprite.layers[1].id])
        XCTAssertEqual(doc.sprite.celZIndex.count, 1)
    }

    func testSavedMovedAndExportedToAseprite() throws {
        let doc = makeDocument()
        doc.activeLayerID = doc.sprite.layers[0].id
        doc.goToFrame(0)
        doc.arrange(.front, everyFrame: false)
        let key = doc.sprite.celZIndex.first!.key
        let decoded = try JSONDecoder().decode(Sprite.self, from: try JSONEncoder().encode(doc.sprite))
        XCTAssertEqual(decoded.celZIndex, doc.sprite.celZIndex)
        let reread = try AsepriteFile.read(try AsepriteFile.write(doc.sprite))
        XCTAssertEqual(reread.composite(frameIndex: 0), doc.sprite.composite(frameIndex: 0))
        // Moving the cel to another frame takes its z-index along.
        doc.moveCel(from: (key.layer, 0), to: (key.layer, 1))
        XCTAssertEqual(doc.sprite.celZIndex[CelKey(layer: key.layer, frame: doc.sprite.frames[1].id)], 2)
    }
}
