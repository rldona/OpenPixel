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

    /// The editor opens with the newest save, even one still on its way to
    /// the disk, and gets the same document each time it asks.
    func testOpeningUsesTheLatestSaveAndKeepsTheDocument() async throws {
        let store = makeStore()
        let id = try store.create(name: "Walk", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        let first = try store.open(id)
        XCTAssertTrue(try store.open(id) === first, "the editor asks again while it shows")
        first.name = "Run"
        store.save(first)
        store.forgetOpened()
        let reopened = try store.open(id)
        XCTAssertFalse(reopened === first)
        XCTAssertEqual(reopened.name, "Run", "the save not flushed yet")
        await store.flush()
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

    func testFoldersGoInsideFolders() throws {
        let store = makeStore()
        let characters = try store.createFolder(name: "Characters")
        let dummy = try store.createFolder(name: "Dummy", in: characters)
        let walk = try store.create(name: "Walk", sprite: blank, in: dummy)
        XCTAssertEqual(store.folders(in: nil).map(\.id), [characters])
        XCTAssertEqual(store.folders(in: characters).map(\.id), [dummy])
        XCTAssertEqual(store.path(to: dummy).map(\.name), ["Characters", "Dummy"])
        XCTAssertEqual(store.allItems(in: characters).map(\.id), [walk], "a folder shows what its folders hold")
        XCTAssertTrue(store.items(in: characters).isEmpty)

        let reopened = makeStore(store.directory)
        XCTAssertEqual(reopened.folder(dummy)?.parent, characters, "the nesting is saved")
    }

    func testAFolderCantGoInsideItself() throws {
        let store = makeStore()
        let outer = try store.createFolder(name: "Outer")
        let inner = try store.createFolder(name: "Inner", in: outer)
        try store.moveFolder(outer, to: inner)
        XCTAssertNil(store.folder(outer)?.parent, "not inside its own folder")
        try store.moveFolder(outer, to: outer)
        XCTAssertNil(store.folder(outer)?.parent)
        try store.moveFolder(inner, to: nil)
        XCTAssertNil(store.folder(inner)?.parent)
        try store.moveFolder(outer, to: inner)
        XCTAssertEqual(store.folder(outer)?.parent, inner, "once apart it can")
    }

    func testDeletingANestedFolderMovesItsContentUpALevel() throws {
        let store = makeStore()
        let characters = try store.createFolder(name: "Characters")
        let dummy = try store.createFolder(name: "Dummy", in: characters)
        let poses = try store.createFolder(name: "Poses", in: dummy)
        let walk = try store.create(name: "Walk", sprite: blank, in: dummy)
        try store.deleteFolder(dummy)
        XCTAssertEqual(store.folderOf[walk], characters)
        XCTAssertEqual(store.folder(poses)?.parent, characters)
    }

    func testNamesAreUniqueOnlyBesideEachOther() throws {
        let store = makeStore()
        let a = try store.createFolder(name: "A")
        let b = try store.createFolder(name: "B")
        let first = try store.createFolder(name: "Walk", in: a)
        let second = try store.createFolder(name: "Walk", in: b)
        XCTAssertEqual(store.folder(first)?.name, "Walk")
        XCTAssertEqual(store.folder(second)?.name, "Walk")
    }

    func testACopiedProjectPastesAsANewProject() throws {
        let store = makeStore()
        let walk = try store.create(name: "Walk", sprite: blank)
        let folder = try store.createFolder(name: "Dummy")
        store.copy([.project(walk)])
        try store.paste(into: folder)
        XCTAssertEqual(store.items(in: folder).map(\.name), ["Walk"], "a copy elsewhere keeps the name")
        XCTAssertNotEqual(store.items(in: folder).first?.id, walk)
        try store.paste(into: nil)
        XCTAssertEqual(Set(store.items(in: nil).map(\.name)), ["Walk", "Walk" + L10n.string(" (copy)")], "beside the original it's a copy")
        XCTAssertEqual(store.copied, [.project(walk)], "it can be pasted again")
    }

    func testACopiedFolderPastesWithEverythingInsideInItsOrder() throws {
        let store = makeStore()
        let dummy = try store.createFolder(name: "Dummy")
        let inner = try store.createFolder(name: "Poses", in: dummy)
        let walk = try store.create(name: "Walk", sprite: blank, in: dummy)
        let idle = try store.create(name: "Idle", sprite: blank, in: dummy)
        _ = try store.create(name: "Sit", sprite: blank, in: inner)
        try store.place(walk, by: idle, after: false, in: dummy)
        try store.place(inner, by: idle, after: true, in: dummy)
        store.copy([.folder(dummy)])
        try store.paste(into: dummy)

        let copy = try XCTUnwrap(store.folders(in: dummy).first { $0.name == "Dummy" }, "pasted into itself, once")
        XCTAssertEqual(store.entries(in: copy.id).map(\.name), ["Walk", "Idle", "Poses"], "in the same order")
        let poses = try XCTUnwrap(store.folders(in: copy.id).first)
        XCTAssertEqual(store.items(in: poses.id).map(\.name), ["Sit"])
        XCTAssertNil(store.folders(in: poses.id).first, "the copy doesn't copy itself")
        XCTAssertEqual(store.items(in: dummy).count, 2, "the original keeps its projects")

        try store.paste(into: nil)
        XCTAssertEqual(Set(store.folders(in: nil).map(\.name)), ["Dummy", "Dummy" + L10n.string(" (copy)")])
        let reopened = makeStore(store.directory)
        XCTAssertEqual(reopened.folders.count, 8, "the copy inside came along, and it all survives a reload")
    }

    func testEverythingKeepsTheOrderItIsDraggedInto() throws {
        let store = makeStore()
        let folder = try store.createFolder(name: "Dummy")
        let a = try store.create(name: "A", sprite: blank, in: folder)
        let b = try store.create(name: "B", sprite: blank, in: folder)
        let c = try store.create(name: "C", sprite: blank, in: folder)
        let inner = try store.createFolder(name: "Inner", in: folder)
        func ids() -> [UUID] { store.entries(in: folder).map(\.id) }
        XCTAssertEqual(ids(), [inner, c, b, a], "folders, then projects newest first, until reordered")
        try store.place(inner, by: a, after: true, in: folder)
        XCTAssertEqual(ids(), [c, b, a, inner], "a folder goes among the projects")
        try store.place(a, by: c, after: false, in: folder)
        XCTAssertEqual(ids(), [a, c, b, inner])

        try store.rename(b, to: "B2")
        XCTAssertEqual(ids(), [a, c, b, inner], "editing doesn't move it")
        let d = try store.create(name: "D", sprite: blank, in: folder)
        XCTAssertEqual(ids(), [d, a, c, b, inner], "a new one comes first")
        XCTAssertEqual(makeStore(store.directory).entries(in: folder).map(\.id), [d, a, c, b, inner], "the order is saved")
    }

    func testTheHomeScreenCanBeOrderedToo() throws {
        let store = makeStore()
        let old = try store.create(name: "Old", sprite: blank)
        let new = try store.create(name: "New", sprite: blank)
        let folder = try store.createFolder(name: "Dummy")
        XCTAssertEqual(store.entries(in: nil).map(\.id), [folder, new, old])
        try store.place(folder, by: old, after: true, in: nil)
        try store.place(old, by: new, after: false, in: nil)
        XCTAssertEqual(store.entries(in: nil).map(\.id), [old, new, folder])
        try store.place(old, by: old, after: true, in: nil)
        XCTAssertEqual(store.entries(in: nil).map(\.id), [old, new, folder], "onto itself: nothing")
    }
}
