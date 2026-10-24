import XCTest
@testable import OpenPixel

@MainActor
final class LayerMergeTests: XCTestCase {
    private let red = PixelColor(r: 255, g: 0, b: 0)

    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        doc.primary = .black
        return doc
    }

    private func dot(_ doc: SpriteDocument, _ x: Int, _ y: Int, _ color: PixelColor) {
        doc.primary = color
        doc.beginStroke(at: PixelPoint(x: x, y: y))
        doc.endStroke()
    }

    private func pixel(_ doc: SpriteDocument, layer: Int, frame: Int = 0, _ x: Int, _ y: Int) -> PixelColor {
        doc.sprite.cel(layer: doc.sprite.layers[layer].id, frame: doc.sprite.frames[frame].id)?[x, y] ?? .clear
    }

    func testMergeDownDrawsWithOpacityAndRemovesTheLayer() {
        let doc = makeDocument()
        dot(doc, 0, 0, .black)
        doc.addLayer()
        dot(doc, 0, 0, red)
        dot(doc, 1, 0, red)
        doc.setOpacity(0.5, layer: doc.activeLayerID)
        let lower = doc.sprite.layers[0].id
        doc.mergeDown(doc.activeLayerID)
        XCTAssertEqual(doc.sprite.layers.count, 1)
        XCTAssertEqual(doc.activeLayerID, lower)
        XCTAssertEqual(Int(pixel(doc, layer: 0, 0, 0).r), 128, accuracy: 1, "half red over black")
        XCTAssertEqual(Int(pixel(doc, layer: 0, 1, 0).a), 128, accuracy: 1)
        doc.undo()
        XCTAssertEqual(doc.sprite.layers.count, 2)
    }

    func testMergeDownUnlinksOnlyTheMergedCel() {
        let doc = makeDocument()
        dot(doc, 0, 0, .black)
        doc.toggleContinuous(doc.activeLayerID)
        doc.addFrame()
        XCTAssertFalse(doc.sprite.links.isEmpty)
        doc.addLayer()
        dot(doc, 2, 2, red)
        doc.mergeDown(doc.activeLayerID)
        XCTAssertEqual(pixel(doc, layer: 0, frame: 1, 2, 2), red)
        XCTAssertEqual(pixel(doc, layer: 0, frame: 0, 2, 2), .clear)
        XCTAssertTrue(doc.sprite.links.isEmpty, "frame 1 got new pixels, so the pair is no longer linked")
    }

    func testFlattenKeepsWhatIsVisible() {
        let doc = makeDocument()
        dot(doc, 0, 0, .black)
        doc.addLayer()
        dot(doc, 1, 1, red)
        doc.addLayer()
        dot(doc, 2, 2, red)
        doc.toggleVisibility(doc.activeLayerID)
        doc.flatten()
        XCTAssertEqual(doc.sprite.layers.count, 1)
        XCTAssertEqual(pixel(doc, layer: 0, 0, 0), .black)
        XCTAssertEqual(pixel(doc, layer: 0, 1, 1), red)
        XCTAssertEqual(pixel(doc, layer: 0, 2, 2), .clear, "hidden layers are dropped")
        doc.undo()
        XCTAssertEqual(doc.sprite.layers.count, 3)
    }

    func testNewLayerFromSelection() {
        let doc = makeDocument()
        dot(doc, 0, 0, .black)
        dot(doc, 3, 3, .black)
        doc.select(.selectRectangle)
        doc.selectionFitsContent = false
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 1, y: 1))
        doc.endStroke()
        doc.newLayerFromSelection(cut: false)
        XCTAssertEqual(doc.sprite.layers.count, 2)
        XCTAssertEqual(doc.activeLayerID, doc.sprite.layers[1].id)
        XCTAssertEqual(pixel(doc, layer: 1, 0, 0), .black)
        XCTAssertEqual(pixel(doc, layer: 1, 3, 3), .clear)
        XCTAssertEqual(pixel(doc, layer: 0, 0, 0), .black, "copy leaves the source")

        doc.selectCel(layer: doc.sprite.layers[0].id, frameIndex: 0)
        doc.newLayerFromSelection(cut: true)
        XCTAssertEqual(doc.sprite.layers.count, 3)
        XCTAssertEqual(pixel(doc, layer: 0, 0, 0), .clear, "cut clears the source")
        XCTAssertEqual(pixel(doc, layer: 1, 0, 0), .black)
        doc.undo()
        XCTAssertEqual(pixel(doc, layer: 0, 0, 0), .black, "one undo step")
    }
}
