import XCTest
@testable import OpenPixel

@MainActor
final class GalleryAnimationTests: XCTestCase {
    func testAnimatedSpritesGiveTheirFramesAndStillOnesDont() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DocumentStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        var sprite = Sprite.blank(width: 4, height: 4, background: nil, palette: [])
        sprite.frames.append(Frame(duration: 250))
        let animated = try store.create(name: "Walk", sprite: sprite)
        _ = try store.create(name: "Still", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        store.reload()
        let walk = try XCTUnwrap(store.items.first { $0.id == animated })
        let animation = await store.animation(for: walk)
        XCTAssertEqual(animation?.frames.count, 2)
        XCTAssertEqual(animation?.durations, [100, 250])
        let still = try XCTUnwrap(store.items.first { $0.id != animated })
        let none = await store.animation(for: still)
        XCTAssertNil(none)
    }
}
