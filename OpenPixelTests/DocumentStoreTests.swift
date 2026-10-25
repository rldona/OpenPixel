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

    func testDeletingASpriteWhoseFileIsGoneDoesNotFail() throws {
        let store = makeStore()
        let id = try store.create(name: "Gone", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        try FileManager.default.removeItem(at: store.directory.appendingPathComponent("\(id.uuidString).openpixel"))
        XCTAssertNoThrow(try store.delete(id))
        XCTAssertFalse(store.items.contains { $0.id == id })
    }
}
