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
        doc.arrange(.forward)
        XCTAssertEqual(names(doc), [start[0], start[2], start[1], start[3]])
        doc.arrange(.backward)
        doc.arrange(.backward)
        XCTAssertEqual(names(doc), [start[1], start[0], start[2], start[3]])
        XCTAssertFalse(doc.canArrange(forward: false), "already at the back")
    }

    func testFrontAndBackGoAllTheWay() {
        let doc = makeDocument()
        let start = names(doc)
        doc.activeLayerID = doc.sprite.layers[1].id
        doc.arrange(.front)
        XCTAssertEqual(names(doc).last, start[1])
        doc.arrange(.back)
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
        doc.arrange(.front)
        XCTAssertTrue(doc.isTransforming, "the transform stays open")
        XCTAssertEqual(names(doc).last, start[0])
        doc.cancelTransform()
        XCTAssertEqual(names(doc), start, "cancel puts the order back too")
        doc.beginTransform()
        doc.arrange(.front)
        doc.applyTransform()
        doc.undo()
        XCTAssertEqual(names(doc), start)
    }
}
