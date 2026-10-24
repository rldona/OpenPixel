import XCTest
@testable import OpenPixel

@MainActor
final class SliceTests: XCTestCase {
    private func makeDocument(frames: Int = 1) -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 16, height: 16, background: nil, palette: []))
        doc.primary = .black
        for _ in 1..<frames { doc.addFrame(empty: true) }
        doc.goToFrame(0)
        doc.select(.slice)
        return doc
    }

    private func drag(_ doc: SpriteDocument, _ a: (Int, Int), _ b: (Int, Int)) {
        doc.beginStroke(at: PixelPoint(x: a.0, y: a.1))
        doc.continueStroke(to: PixelPoint(x: b.0, y: b.1))
        doc.endStroke()
    }

    func testDrawMoveAndResize() {
        let doc = makeDocument()
        drag(doc, (2, 2), (9, 7))
        XCTAssertEqual(doc.sprite.slices.count, 1)
        XCTAssertEqual(doc.activeSliceKey?.bounds, PixelRect(minX: 2, minY: 2, maxX: 9, maxY: 7))
        XCTAssertEqual(doc.sprite.slices[0].name, L10n.string("Slice %d", 1))
        drag(doc, (5, 5), (6, 6))
        XCTAssertEqual(doc.activeSliceKey?.bounds, PixelRect(minX: 3, minY: 3, maxX: 10, maxY: 8), "dragged inside: moved")
        drag(doc, (10, 8), (12, 12))
        XCTAssertEqual(doc.activeSliceKey?.bounds, PixelRect(minX: 3, minY: 3, maxX: 12, maxY: 12), "dragged the corner: resized")
        doc.undo(); doc.undo(); doc.undo()
        XCTAssertTrue(doc.sprite.slices.isEmpty, "each drag is one undo step")
    }

    func testTapPicksASliceAndDrawingElsewhereAddsOne() {
        let doc = makeDocument()
        drag(doc, (0, 0), (3, 3))
        let first = doc.activeSliceID
        drag(doc, (8, 8), (12, 12))
        XCTAssertEqual(doc.sprite.slices.count, 2)
        doc.beginStroke(at: PixelPoint(x: 1, y: 1))
        doc.endStroke()
        XCTAssertEqual(doc.activeSliceID, first)
        doc.deleteSlice(first!)
        XCTAssertEqual(doc.sprite.slices.count, 1)
        XCTAssertNil(doc.activeSliceID)
    }

    func testChangesOnLaterFramesMakeKeys() throws {
        let doc = makeDocument(frames: 3)
        drag(doc, (0, 0), (3, 3))
        doc.goToFrame(2)
        drag(doc, (1, 1), (5, 1))
        let slice = doc.sprite.slices[0]
        XCTAssertEqual(slice.keys.count, 2)
        XCTAssertEqual(slice.key(at: 0, frames: doc.sprite.frames)?.bounds.minX, 0)
        XCTAssertEqual(slice.key(at: 1, frames: doc.sprite.frames)?.bounds.minX, 0, "the first key holds until the next")
        XCTAssertEqual(slice.key(at: 2, frames: doc.sprite.frames)?.bounds.minX, 4)
        doc.deleteFrame(at: 2)
        XCTAssertEqual(doc.sprite.slices[0].keys.count, 1, "a deleted frame's key goes")
        let decoded = try JSONDecoder().decode(Sprite.self, from: JSONEncoder().encode(doc.sprite))
        XCTAssertEqual(decoded.slices, doc.sprite.slices)
    }

    func testCenterAndPivot() {
        let doc = makeDocument()
        drag(doc, (0, 0), (8, 8))
        doc.editActiveSlice { $0.center = PixelRect(minX: 3, minY: 3, maxX: 5, maxY: 5); $0.pivot = PixelPoint(x: 4, y: 8) }
        XCTAssertEqual(doc.activeSliceKey?.center?.width, 3)
        XCTAssertEqual(doc.activeSliceKey?.pivot, PixelPoint(x: 4, y: 8))
    }

    func testExportedDataAndSlicePNGs() throws {
        let doc = makeDocument(frames: 2)
        drag(doc, (0, 0), (3, 1))
        doc.editActiveSlice { $0.pivot = PixelPoint(x: 1, y: 1) }
        doc.select(.pencil)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.endStroke()
        let data = try Exporter.sheetData(doc.sprite, frames: [0, 1], scale: 2, imageName: "doc-sheet.png", baseName: "doc")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let frames = try XCTUnwrap(json["frames"] as? [[String: Any]])
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual((frames[1]["frame"] as? [String: Int])?["x"], 32)
        let meta = try XCTUnwrap(json["meta"] as? [String: Any])
        let slices = try XCTUnwrap(meta["slices"] as? [[String: Any]])
        let key = try XCTUnwrap((slices[0]["keys"] as? [[String: Any]])?.first)
        XCTAssertEqual((key["bounds"] as? [String: Int])?["w"], 8, "scaled")
        XCTAssertEqual((key["pivot"] as? [String: Int])?["x"], 2)
        let pieces = Exporter.sliceImages(doc.sprite, frameIndex: 0)
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(pieces[0].image.width, 4)
        XCTAssertEqual(pieces[0].image[0, 0], .black)
        let urls = try Exporter.exportFiles(doc.sprite, name: "doc", frameIndex: 0, format: .spriteSheet, scale: 1, includeData: true)
        XCTAssertEqual(urls.map(\.pathExtension), ["png", "json"])
    }
}

@MainActor
final class SliceTapTests: XCTestCase {
    func testTapOnEmptyCanvasDeselectsInsteadOfAddingASlice() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 16, height: 16, background: nil, palette: []))
        doc.select(.slice)
        doc.beginStroke(at: PixelPoint(x: 1, y: 1))
        doc.continueStroke(to: PixelPoint(x: 6, y: 6))
        doc.endStroke()
        XCTAssertNotNil(doc.activeSliceID)
        doc.beginStroke(at: PixelPoint(x: 12, y: 12))
        doc.endStroke()
        XCTAssertEqual(doc.sprite.slices.count, 1)
        XCTAssertNil(doc.activeSliceID)
        XCTAssertTrue(doc.canUndo)
        doc.undo()
        XCTAssertTrue(doc.sprite.slices.isEmpty, "the tap left no undo step of its own")
    }
}
