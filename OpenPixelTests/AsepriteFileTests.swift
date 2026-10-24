import XCTest
@testable import OpenPixel

final class AsepriteFileTests: XCTestCase {
    private let red = PixelColor(r: 255, g: 0, b: 0)
    private let blue = PixelColor(r: 0, g: 0, b: 255, a: 128)

    /// Two frames, a group with two layers, a background, a tag, a slice and a linked cel.
    private func makeSprite() -> Sprite {
        var sprite = Sprite.blank(width: 8, height: 6, background: .white, palette: [.black, .white, red])
        let background = sprite.layers[0]
        sprite.insertFrame(Frame(duration: 250), at: 1)
        var group = Layer(name: "Group", opacity: 0.5)
        group.isGroup = true
        group.isExpanded = false
        var a = Layer(name: "A", isLocked: true)
        a.parent = group.id
        a.blendMode = .multiply
        var b = Layer(name: "B", isVisible: false)
        b.parent = group.id
        sprite.layers = [background, a, b, group]
        let f0 = sprite.frames[0].id, f1 = sprite.frames[1].id
        sprite.cels[CelKey(layer: background.id, frame: f1)] = PixelImage(width: 8, height: 6, fill: .black)
        var dot = PixelImage(width: 8, height: 6)
        dot[2, 3] = red
        dot[5, 1] = blue
        sprite.cels[CelKey(layer: a.id, frame: f0)] = dot
        sprite.cels[CelKey(layer: a.id, frame: f1)] = dot
        sprite.link([CelKey(layer: a.id, frame: f0), CelKey(layer: a.id, frame: f1)])
        sprite.celOpacity[CelKey(layer: a.id, frame: f0)] = 0.4
        sprite.celOpacity[CelKey(layer: a.id, frame: f1)] = 0.4
        var corner = PixelImage(width: 8, height: 6)
        corner[7, 5] = red
        sprite.cels[CelKey(layer: b.id, frame: f1)] = corner
        sprite.tags = [FrameTag(name: "walk", from: 0, to: 1, color: PixelColor(r: 0, g: 144, b: 255), direction: .pingPong, repeatCount: 3)]
        sprite.slices = [Slice(name: "hit", color: PixelColor(r: 255, g: 0, b: 128), keys: [
            SliceKey(frame: f0, bounds: PixelRect(minX: 1, minY: 1, maxX: 4, maxY: 3), center: PixelRect(minX: 1, minY: 1, maxX: 2, maxY: 1), pivot: PixelPoint(x: 2, y: 2)),
            SliceKey(frame: f1, bounds: PixelRect(minX: 2, minY: 1, maxX: 5, maxY: 3))
        ])]
        sprite.grid = GridSettings(width: 4, height: 3, offsetX: 1, offsetY: 0)
        sprite.pixelRatio = PixelRatio(width: 2, height: 1)
        return sprite
    }

    func testRoundTripKeepsTheSprite() throws {
        let original = makeSprite()
        let read = try AsepriteFile.read(try AsepriteFile.write(original))

        XCTAssertEqual(read.width, 8)
        XCTAssertEqual(read.height, 6)
        XCTAssertEqual(read.frames.map(\.duration), [100, 250])
        XCTAssertEqual(read.palette, original.palette)
        XCTAssertEqual(read.grid, original.grid)
        XCTAssertEqual(read.pixelRatio, PixelRatio(width: 2, height: 1))
        XCTAssertEqual(read.layers.map(\.name), [original.layers[0].name, "A", "B", "Group"], "groups stay above their children")
        XCTAssertTrue(read.layers[0].isBackground)
        XCTAssertEqual(read.layers[1].parent, read.layers[3].id)
        XCTAssertTrue(read.layers[1].isLocked)
        XCTAssertEqual(read.layers[1].blendMode, .multiply)
        XCTAssertFalse(read.layers[2].isVisible)
        XCTAssertTrue(read.layers[3].isGroup)
        XCTAssertFalse(read.layers[3].isExpanded)
        XCTAssertEqual(read.layers[3].opacity, 0.5, accuracy: 0.01)

        for i in original.frames.indices {
            XCTAssertEqual(read.composite(frameIndex: i), original.composite(frameIndex: i), "frame \(i) looks the same")
        }
        let a = read.layers[1].id
        XCTAssertNotNil(read.links[CelKey(layer: a, frame: read.frames[0].id)])
        XCTAssertEqual(read.links[CelKey(layer: a, frame: read.frames[0].id)], read.links[CelKey(layer: a, frame: read.frames[1].id)], "linked cels stay linked")
        XCTAssertEqual(read.celOpacity[CelKey(layer: a, frame: read.frames[1].id)] ?? 1, 0.4, accuracy: 0.01)

        XCTAssertEqual(read.tags.count, 1)
        XCTAssertEqual(read.tags[0].name, "walk")
        XCTAssertEqual(read.tags[0].direction, .pingPong)
        XCTAssertEqual(read.tags[0].repeatCount, 3)
        XCTAssertEqual(read.tags[0].color, PixelColor(r: 0, g: 144, b: 255))

        XCTAssertEqual(read.slices.count, 1)
        XCTAssertEqual(read.slices[0].name, "hit")
        XCTAssertEqual(read.slices[0].color, PixelColor(r: 255, g: 0, b: 128))
        XCTAssertEqual(read.slices[0].keys.map(\.bounds), original.slices[0].keys.map(\.bounds))
        XCTAssertEqual(read.slices[0].keys[0].center, PixelRect(minX: 1, minY: 1, maxX: 2, maxY: 1))
        XCTAssertEqual(read.slices[0].keys[0].pivot, PixelPoint(x: 2, y: 2))
        XCTAssertEqual(read.slices[0].keys[1].frame, read.frames[1].id)
    }

    func testTilemapRoundTrip() throws {
        var sprite = Sprite.blank(width: 8, height: 8, background: nil, palette: [])
        var tileset = Tileset(tileWidth: 4, tileHeight: 4)
        tileset.tiles.append(PixelImage(width: 4, height: 4, fill: red))
        sprite.layers[0].tileset = tileset
        let key = CelKey(layer: sprite.layers[0].id, frame: sprite.frames[0].id)
        var map = TileMap(columns: 2, rows: 2)
        map[1, 0] = 1
        map[0, 1] = 1
        sprite.tilemaps[key] = map
        sprite.cels[key] = sprite.render(map, with: tileset)

        let read = try AsepriteFile.read(try AsepriteFile.write(sprite))
        XCTAssertEqual(read.layers[0].tileset, tileset)
        let readKey = CelKey(layer: read.layers[0].id, frame: read.frames[0].id)
        XCTAssertEqual(read.tilemaps[readKey], map)
        XCTAssertEqual(read.cels[readKey], sprite.cels[key])
    }

    func testRejectsOtherFiles() {
        XCTAssertThrowsError(try AsepriteFile.read(Data("not a sprite".utf8)))
        XCTAssertThrowsError(try AsepriteFile.read(Data(repeating: 0, count: 200)))
    }

    func testZlibRoundTrip() throws {
        let bytes = (0..<10_000).map { UInt8(truncatingIfNeeded: $0 * 7 / 3) }
        XCTAssertEqual(try Zlib.inflate(try Zlib.deflate(bytes), size: bytes.count), bytes)
    }
}
