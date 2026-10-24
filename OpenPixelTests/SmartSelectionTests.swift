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
}
