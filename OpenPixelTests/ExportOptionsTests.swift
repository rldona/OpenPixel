import ImageIO
import XCTest
@testable import OpenPixel

final class ExportOptionsTests: XCTestCase {
    private let red = PixelColor(r: 255, g: 0, b: 0)

    /// Four frames with a pixel at x = frame index, a tag over frames 1–3 and two layers.
    private func makeSprite() -> Sprite {
        var sprite = Sprite.blank(width: 4, height: 2, background: nil, palette: [])
        for i in 1..<4 { sprite.insertFrame(Frame(duration: 100 * (i + 1)), at: i) }
        sprite.layers.append(Layer(name: "Top"))
        for (i, frame) in sprite.frames.enumerated() {
            var image = PixelImage(width: 4, height: 2)
            image[i, 0] = red
            sprite.cels[CelKey(layer: sprite.layers[0].id, frame: frame.id)] = image
        }
        var top = PixelImage(width: 4, height: 2)
        top[0, 1] = .black
        sprite.cels[CelKey(layer: sprite.layers[1].id, frame: sprite.frames[0].id)] = top
        sprite.tags = [FrameTag(name: "run", from: 1, to: 3, color: red, direction: .pingPong, repeatCount: 2)]
        return sprite
    }

    func testFrameChoices() {
        let sprite = makeSprite()
        var options = ExportOptions()
        XCTAssertEqual(Exporter.frames(sprite, options, current: 2), [0, 1, 2, 3])
        options.frames = .current
        XCTAssertEqual(Exporter.frames(sprite, options, current: 2), [2])
        options.frames = .tag(sprite.tags[0].id)
        XCTAssertEqual(Exporter.frames(sprite, options, current: 0), [1, 2, 3])
        options.frames = .range(from: 2, to: 0)
        XCTAssertEqual(Exporter.frames(sprite, options, current: 0), [0, 1, 2], "a reversed range still covers its frames")
        options.frames = .range(from: 1, to: 99)
        XCTAssertEqual(Exporter.frames(sprite, options, current: 0), [1, 2, 3], "clamped to the sprite")
    }

    func testDirectionFollowsTheTagUnlessChosen() {
        let sprite = makeSprite()
        var options = ExportOptions(frames: .tag(sprite.tags[0].id))
        let tagged = Exporter.playback(sprite, options, current: 0)
        XCTAssertEqual(tagged.frames, [1, 2, 3, 2], "the tag's ping-pong")
        XCTAssertEqual(tagged.loopCount, 2)
        options.direction = .reverse
        XCTAssertEqual(Exporter.playback(sprite, options, current: 0).frames, [3, 2, 1])
        XCTAssertEqual(Exporter.playback(sprite, ExportOptions(direction: .pingPong), current: 0).frames, [0, 1, 2, 3, 2, 1])
    }

    func testPNGSequenceIsNumberedInPlayOrder() throws {
        let sprite = makeSprite()
        let urls = try Exporter.exportFiles(sprite, name: "hero", frameIndex: 0,
                                            options: ExportOptions(format: .pngSequence, frames: .tag(sprite.tags[0].id), scale: 1))
        XCTAssertEqual(urls.map(\.lastPathComponent), ["hero-run_001.png", "hero-run_002.png", "hero-run_003.png", "hero-run_004.png"])
        let images = try urls.map { try XCTUnwrap(PixelImage(cgImage: XCTUnwrap(CGImageSourceCreateImageAtIndex(XCTUnwrap(CGImageSourceCreateWithURL($0 as CFURL, nil)), 0, nil)))) }
        XCTAssertEqual(images.map { image in (0..<4).first { image[$0, 0] == red } }, [1, 2, 3, 2])
    }

    func testOneLayerScaleAndPixelRatio() throws {
        var sprite = makeSprite()
        sprite.pixelRatio = PixelRatio(width: 2, height: 1)
        let options = ExportOptions(format: .png, layer: sprite.layers[1].id, scale: 2)
        let url = try XCTUnwrap(Exporter.exportFiles(sprite, name: "a", frameIndex: 0, options: options).first)
        let image = try XCTUnwrap(PixelImage(cgImage: XCTUnwrap(CGImageSourceCreateImageAtIndex(XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil)), 0, nil))))
        XCTAssertEqual(image.width, 16, "4 px × scale 2 × pixel width 2")
        XCTAssertEqual(image.height, 4)
        XCTAssertEqual(image[0, 2], .black, "the chosen layer")
        XCTAssertEqual(image[0, 0].a, 0, "the other layer is left out")

        var square = options
        square.applyPixelRatio = false
        XCTAssertEqual(Exporter.scales(sprite, square).x, 2)
    }

    func testTwitterFixes() throws {
        let sprite = makeSprite()
        let gif = try Exporter.gifData(sprite, frames: [0, 1, 2, 3], scale: 1, forTwitter: true)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(gif as CFData, nil))
        let delays = (0..<4).map { i -> Double in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gifInfo = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            return gifInfo?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? -1
        }
        XCTAssertEqual(delays, [0.1, 0.2, 0.3, 0.1], "the last frame plays a quarter of its 400 ms")

        let opaque = PixelImage(width: 2, height: 2, fill: red)
        let png = try Exporter.pngData(opaque, forTwitter: true)
        let read = try XCTUnwrap(PixelImage(cgImage: XCTUnwrap(CGImageSourceCreateImageAtIndex(XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil)), 0, nil))))
        XCTAssertEqual(read[1, 1].a, 254, "one pixel not quite opaque")
        XCTAssertEqual(read[0, 0].a, 255)
    }

    func testAsepriteExportAndAnimatedGIFImport() throws {
        let sprite = makeSprite()
        let url = try XCTUnwrap(Exporter.exportFiles(sprite, name: "hero", frameIndex: 0, options: ExportOptions(format: .aseprite)).first)
        XCTAssertEqual(url.pathExtension, "aseprite")
        let back = try AsepriteFile.read(Data(contentsOf: url))
        XCTAssertEqual(back.frames.count, 4)
        XCTAssertEqual(back.tags.first?.name, "run")

        let gif = try Exporter.gifData(sprite, scale: 1)
        let imported = try DocumentStore.sprite(fromImage: gif)
        XCTAssertEqual(imported.frames.map(\.duration), [100, 200, 300, 400])
        for i in 0..<4 { XCTAssertEqual(imported.composite(frameIndex: i), sprite.composite(frameIndex: i)) }
    }
}
