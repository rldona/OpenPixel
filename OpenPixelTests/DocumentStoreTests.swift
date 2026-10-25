import XCTest
@testable import OpenPixel

@MainActor
final class DocumentStoreTests: XCTestCase {
    private func makeStore() -> DocumentStore {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return DocumentStore(directory: directory)
    }

    /// Edit, go back, delete, open another sprite: the deleted one stays gone.
    func testADeletedSpriteDoesNotComeBackAfterItsSave() async throws {
        let store = makeStore()
        let id = try store.create(name: "Ghost", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        let other = try store.create(name: "Other", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        let document = try store.load(id)
        document.name = "Ghost 2"
        store.save(document)
        try store.delete(id)
        await store.flush()
        XCTAssertFalse(store.items.contains { $0.id == id }, "no card for a deleted sprite")
        XCTAssertTrue(store.items.contains { $0.id == other })
        try await Task.sleep(for: .milliseconds(100))
        store.reload()
        XCTAssertFalse(store.items.contains { $0.id == id }, "and no file either")
    }

    func testNewSpritesGetNumberedNames() throws {
        let store = makeStore()
        let blank = Sprite.blank(width: 4, height: 4, background: nil, palette: [])
        try store.create(name: "Untitled", sprite: blank)
        try store.create(name: "Untitled", sprite: blank)
        try store.create(name: "Untitled", sprite: blank)
        try store.create(name: "Walk", sprite: blank)
        XCTAssertEqual(Set(store.items.map(\.name)), ["Untitled", "Untitled 2", "Untitled 3", "Walk"])
    }

    func testDeletingASpriteWhoseFileIsGoneDoesNotFail() throws {
        let store = makeStore()
        let id = try store.create(name: "Gone", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        try FileManager.default.removeItem(at: store.directory.appendingPathComponent("\(id.uuidString).openpixel"))
        XCTAssertNoThrow(try store.delete(id))
        XCTAssertFalse(store.items.contains { $0.id == id })
    }
}

@MainActor
final class RecentColorTests: XCTestCase {
    private func stroke(_ doc: SpriteDocument, _ color: PixelColor, at x: Int) {
        doc.primary = color
        doc.beginStroke(at: PixelPoint(x: x, y: 0))
        doc.endStroke()
    }

    func testPaintedColorsAreRememberedNewestFirst() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 16, height: 4, background: nil, palette: []))
        let red = PixelColor(r: 255, g: 0, b: 0), blue = PixelColor(r: 0, g: 0, b: 255)
        stroke(doc, red, at: 0)
        stroke(doc, blue, at: 1)
        stroke(doc, red, at: 2)
        XCTAssertEqual(doc.recentColors, [red, blue], "no duplicates, the latest first")
        doc.select(.eraser)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.endStroke()
        XCTAssertEqual(doc.recentColors, [red, blue], "erasing isn't painting")
        doc.select(.pencil)
        for i in 0..<10 { stroke(doc, PixelColor(r: UInt8(i * 20), g: 50, b: 50), at: i) }
        XCTAssertEqual(doc.recentColors.count, SpriteDocument.recentColorCount)
    }
}
