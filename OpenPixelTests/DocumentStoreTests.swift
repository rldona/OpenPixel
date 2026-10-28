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

    /// Going back, the gallery reads its cards before the editor's last save;
    /// the flush after that save brings the card up to date.
    func testTheCardCatchesUpWithASaveMadeAfterTheGalleryShowed() async throws {
        let store = makeStore()
        let id = try store.create(name: "Old", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        let document = try store.load(id)
        await store.flush()
        store.reload()
        document.name = "New"
        store.save(document)
        await store.flush()
        XCTAssertEqual(store.items.first { $0.id == id }?.name, "New")
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

    /// Export from a gallery card loads the saved sprite, as the editor would,
    /// and exports it without opening it.
    func testAProjectExportsFromTheGalleryWithoutOpeningIt() throws {
        let store = makeStore()
        let id = try store.create(name: "Walk", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        let document = try store.load(id)
        XCTAssertEqual(document.name, "Walk")
        var options = ExportOptions()
        options.format = .gif
        let files = try Exporter.exportFiles(document.sprite, name: document.name, frameIndex: document.activeFrameIndex, options: options)
        XCTAssertEqual(files.map(\.lastPathComponent), ["Walk.gif"])
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

@MainActor
final class ProjectFolderTests: XCTestCase {
    private func makeStore(_ directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)) -> DocumentStore {
        DocumentStore(directory: directory)
    }

    private let blank = Sprite.blank(width: 4, height: 4, background: nil, palette: [])

    func testProjectsGoIntoFoldersAndTheIndexSurvivesAReload() throws {
        let store = makeStore()
        let walk = try store.create(name: "Walk", sprite: blank)
        let idle = try store.create(name: "Idle", sprite: blank)
        let folder = try store.createFolder(name: "Dummy")
        try store.move([walk], to: folder)
        XCTAssertEqual(store.items(in: folder).map(\.id), [walk])
        XCTAssertEqual(store.items(in: nil).map(\.id), [idle], "the home screen shows what's not in a folder")

        let reopened = makeStore(store.directory)
        XCTAssertEqual(reopened.folders.map(\.name), ["Dummy"])
        XCTAssertEqual(reopened.folderOf[walk], folder)
    }

    func testNewImportedAndDuplicatedProjectsStayInTheFolder() throws {
        let store = makeStore()
        let folder = try store.createFolder(name: "Dummy")
        let made = try store.create(name: "Jump", sprite: blank, in: folder)
        try store.duplicate(made)
        XCTAssertEqual(store.items(in: folder).count, 2)
        XCTAssertTrue(store.items(in: nil).isEmpty)
    }

    func testDeletingAFolderKeepsItsProjects() throws {
        let store = makeStore()
        let walk = try store.create(name: "Walk", sprite: blank)
        let folder = try store.createFolder(name: "Dummy")
        try store.move([walk], to: folder)
        try store.deleteFolder(folder)
        XCTAssertTrue(store.folders.isEmpty)
        XCTAssertEqual(store.items(in: nil).map(\.id), [walk], "back on the home screen")
    }

    func testFolderNamesAreUniqueAndDeletedProjectsLeaveTheIndex() throws {
        let store = makeStore()
        try store.createFolder(name: "Dummy")
        let second = try store.createFolder(name: "Dummy")
        XCTAssertEqual(store.folder(second)?.name, "Dummy 2")
        try store.renameFolder(second, to: "  ")
        XCTAssertEqual(store.folder(second)?.name, "Dummy 2", "an empty name is ignored")
        let walk = try store.create(name: "Walk", sprite: blank, in: second)
        try store.delete(walk)
        XCTAssertNil(store.folderOf[walk])
        try store.move([walk], to: nil)
        XCTAssertNil(store.folderOf[walk])
    }
}
