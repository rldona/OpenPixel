import XCTest
@testable import OpenPixel

final class PlaybackTests: XCTestCase {
    func testCycles() {
        XCTAssertEqual(Playback.cycle(from: 0, to: 3, direction: .forward), [0, 1, 2, 3])
        XCTAssertEqual(Playback.cycle(from: 0, to: 3, direction: .reverse), [3, 2, 1, 0])
        XCTAssertEqual(Playback.cycle(from: 0, to: 3, direction: .pingPong), [0, 1, 2, 3, 2, 1])
        XCTAssertEqual(Playback.cycle(from: 0, to: 3, direction: .pingPongReverse), [3, 2, 1, 0, 1, 2])
        XCTAssertEqual(Playback.cycle(from: 2, to: 2, direction: .pingPong), [2])
        XCTAssertEqual(Playback.cycle(from: 4, to: 5, direction: .pingPong), [4, 5])
    }

    func testPlaybackUsesInnermostTag() {
        var sprite = Sprite.blank(width: 1, height: 1, background: nil, palette: [])
        for _ in 0..<5 { sprite.frames.append(Frame()) }
        sprite.tags = [
            FrameTag(name: "todo", from: 0, to: 5, color: .white),
            FrameTag(name: "salto", from: 2, to: 4, color: .black, direction: .pingPong, repeatCount: 2)
        ]
        XCTAssertEqual(sprite.tag(containing: 3)?.name, "salto")
        XCTAssertEqual(sprite.tag(containing: 1)?.name, "todo")
        let playback = sprite.playbackCycle(at: 3)
        XCTAssertEqual(playback.frames, [2, 3, 4, 3])
        XCTAssertEqual(playback.repeatCount, 2)
        sprite.tags = []
        XCTAssertEqual(sprite.playbackCycle(at: 3).frames, [0, 1, 2, 3, 4, 5])
    }
}

final class FrameTagEditingTests: XCTestCase {
    private func sprite(frames: Int, tag: (Int, Int)) -> Sprite {
        var sprite = Sprite.blank(width: 1, height: 1, background: nil, palette: [])
        for _ in 1..<frames { sprite.frames.append(Frame()) }
        sprite.tags = [FrameTag(name: "t", from: tag.0, to: tag.1, color: .white)]
        return sprite
    }

    func testInsertBeforeTagShiftsIt() {
        var s = sprite(frames: 4, tag: (1, 2))
        s.insertFrame(Frame(), at: 0)
        XCTAssertEqual([s.tags[0].from, s.tags[0].to], [2, 3])
    }

    func testInsertInsideOrRightAfterTagExtendsIt() {
        var s = sprite(frames: 4, tag: (1, 2))
        s.insertFrame(Frame(), at: 2)
        XCTAssertEqual([s.tags[0].from, s.tags[0].to], [1, 3])
        s.insertFrame(Frame(), at: 4)
        XCTAssertEqual([s.tags[0].from, s.tags[0].to], [1, 4])
    }

    func testInsertFarAfterTagLeavesIt() {
        var s = sprite(frames: 4, tag: (0, 1))
        s.insertFrame(Frame(), at: 3)
        XCTAssertEqual([s.tags[0].from, s.tags[0].to], [0, 1])
    }

    func testRemoveFrameShrinksAndDropsEmptyTags() {
        var s = sprite(frames: 4, tag: (1, 2))
        s.removeFrame(at: 0)
        XCTAssertEqual([s.tags[0].from, s.tags[0].to], [0, 1])
        s.removeFrame(at: 1)
        XCTAssertEqual([s.tags[0].from, s.tags[0].to], [0, 0])
        s.removeFrame(at: 0)
        XCTAssertTrue(s.tags.isEmpty)
    }

    func testTagsSurviveCodableAndOldFilesDecode() throws {
        let s = sprite(frames: 3, tag: (0, 2))
        let decoded = try JSONDecoder().decode(Sprite.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(decoded.tags, s.tags)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
        json.removeValue(forKey: "tags")
        let legacy = try JSONDecoder().decode(Sprite.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(legacy.tags.isEmpty)
    }
}

@MainActor
final class AnimationDocumentTests: XCTestCase {
    func testAddTagUndoAndUpdateClampsRange() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        doc.addFrame()
        var tag = doc.addTag()
        XCTAssertEqual([tag.from, tag.to], [1, 1])
        tag.from = 0
        tag.to = 9
        tag.name = "  "
        doc.updateTag(tag)
        XCTAssertEqual([doc.sprite.tags[0].from, doc.sprite.tags[0].to], [0, 1])
        XCTAssertEqual(doc.sprite.tags[0].name, "Tag 1")
        doc.undo()
        doc.undo()
        XCTAssertTrue(doc.sprite.tags.isEmpty)
    }

    func testMoveFrameKeepsActiveFrameAndContent() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 2, height: 1, background: nil, palette: []))
        doc.primary = .black
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.endStroke()
        doc.addFrame(empty: true)
        doc.addFrame(empty: true)
        doc.goToFrame(0)
        doc.moveFrame(from: 0, to: 2)
        XCTAssertEqual(doc.activeFrameIndex, 2)
        XCTAssertEqual(doc.sprite.composite(frameIndex: 2)[0, 0], .black)
        XCTAssertEqual(doc.sprite.composite(frameIndex: 0)[0, 0], .clear)
    }

    func testMoveLayerToTarget() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 1, height: 1, background: nil, palette: []))
        let bottom = doc.sprite.layers[0].id
        doc.addLayer()
        doc.addLayer()
        let top = doc.sprite.layers[2].id
        doc.moveLayer(bottom, to: top)
        XCTAssertEqual(doc.sprite.layers.last?.id, bottom)
    }
}

final class AnimationExportTests: XCTestCase {
    func testGIFFollowsTagDirectionAndLoops() throws {
        // Each frame gets a different pixel: ImageIO merges identical consecutive GIF frames.
        var sprite = Sprite.blank(width: 4, height: 1, background: nil, palette: [])
        for _ in 0..<3 { sprite.frames.append(Frame()) }
        for (i, frame) in sprite.frames.enumerated() {
            var image = PixelImage(width: 4, height: 1)
            image[i, 0] = .white
            sprite.cels[CelKey(layer: sprite.layers[0].id, frame: frame.id)] = image
        }
        let tag = FrameTag(name: "t", from: 1, to: 3, color: .white, direction: .pingPong, repeatCount: 3)
        let animation = Exporter.animation(sprite, tag: tag)
        XCTAssertEqual(animation.frames, [1, 2, 3, 2])
        XCTAssertEqual(animation.loopCount, 3)
        let data = try Exporter.gifData(sprite, frames: animation.frames, loopCount: animation.loopCount, scale: 1)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(source), 4)
    }

    func testTinting() {
        var image = PixelImage(width: 2, height: 1)
        image[0, 0] = .white
        let tinted = image.tinted(.black, amount: 0.5)
        XCTAssertEqual(tinted[0, 0], PixelColor(r: 128, g: 128, b: 128))
        XCTAssertEqual(tinted[1, 0], .clear)
    }
}
