import XCTest
@testable import OpenPixel

/// Tapping the timeline's projected frames and layers adds them.
@MainActor
final class TimelineProjectionTests: XCTestCase {
    func testTappingAProjectedCellAddsFramesAndLayersInOneStep() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        let first = doc.sprite.layers[0].id
        doc.extendTimeline(toFrame: 4, layersBelow: 0, layer: first)
        XCTAssertEqual(doc.sprite.frames.count, 5)
        XCTAssertEqual(doc.activeFrameIndex, 4)
        XCTAssertTrue(doc.sprite.frames.dropFirst().allSatisfy { frame in doc.sprite.cels[CelKey(layer: first, frame: frame.id)] == nil }, "empty frames")

        doc.extendTimeline(toFrame: 6, layersBelow: 2)
        XCTAssertEqual(doc.sprite.frames.count, 7)
        XCTAssertEqual(doc.sprite.layers.count, 3)
        XCTAssertEqual(doc.sprite.layers.last?.id, first, "new layers go under the existing ones")
        XCTAssertEqual(doc.activeLayerID, doc.sprite.layers[0].id, "the bottom one, the row tapped")
        XCTAssertEqual(doc.activeFrameIndex, 6)

        doc.undo()
        XCTAssertEqual(doc.sprite.frames.count, 5, "one undo step for frames and layers together")
        XCTAssertEqual(doc.sprite.layers.count, 1)
    }

    func testBackgroundStaysAtTheBottom() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 4, height: 4, background: .white, palette: []))
        doc.extendTimeline(toFrame: nil, layersBelow: 1)
        XCTAssertTrue(doc.sprite.layers[0].isBackground)
        XCTAssertEqual(doc.sprite.layers.count, 2)
    }
}
