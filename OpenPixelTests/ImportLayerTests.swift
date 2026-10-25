import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OpenPixel

@MainActor
final class ImportLayerTests: XCTestCase {
    /// A GIF whose frame `i` has one red pixel at (i, 0), `delay` seconds each.
    private func gif(width: Int, height: Int, frames: Int, delay: Double = 0.2) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames, nil)!
        for i in 0..<frames {
            var image = PixelImage(width: width, height: height)
            image[i, 0] = PixelColor(r: 255, g: 0, b: 0)
            let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary
            CGImageDestinationAddImage(destination, image.makeCGImage()!, properties)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func cel(_ doc: SpriteDocument, layer: UUID, frame: Int) -> PixelImage? {
        doc.sprite.cel(layer: layer, frame: doc.sprite.frames[frame].id)
    }

    func testAGIFBecomesALayerWithAFramePerGIFFrame() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 8, background: nil, palette: []))
        let layersBefore = doc.sprite.layers.count
        XCTAssertTrue(doc.importLayer(imageData: gif(width: 4, height: 4, frames: 3), name: "Walk"))

        XCTAssertEqual(doc.sprite.layers.count, layersBefore + 1)
        XCTAssertEqual(doc.sprite.frames.count, 3, "the missing frames are added")
        XCTAssertEqual(doc.sprite.frames[2].duration, 200, "new frames take the GIF's durations")
        let layer = doc.activeLayer!
        XCTAssertEqual(layer.name, "Walk")
        for i in 0..<3 {
            // A 4×4 GIF is centered on the 8×8 sprite: (i, 0) lands at (i + 2, 2).
            XCTAssertEqual(cel(doc, layer: layer.id, frame: i)?[i + 2, 2], PixelColor(r: 255, g: 0, b: 0), "frame \(i)")
        }

        doc.undo()
        XCTAssertEqual(doc.sprite.layers.count, layersBefore, "one undo step")
        XCTAssertEqual(doc.sprite.frames.count, 1)
    }

    func testItStartsAtTheActiveFrameAndKeepsExistingDurations() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        doc.addFrame(empty: true)
        doc.setDuration(500, frameIndex: 1)
        doc.goToFrame(1)
        doc.importLayer(imageData: gif(width: 4, height: 4, frames: 2), name: "GIF")

        let layer = doc.activeLayer!
        XCTAssertEqual(doc.sprite.frames.count, 3)
        XCTAssertNil(cel(doc, layer: layer.id, frame: 0), "frames before the active one stay empty")
        XCTAssertEqual(cel(doc, layer: layer.id, frame: 1)?[0, 0], PixelColor(r: 255, g: 0, b: 0))
        XCTAssertEqual(cel(doc, layer: layer.id, frame: 2)?[1, 0], PixelColor(r: 255, g: 0, b: 0))
        XCTAssertEqual(doc.sprite.frames[1].duration, 500, "existing frames keep their duration")
    }

    func testABiggerImageIsCroppedAroundItsCenter() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 2, height: 2, background: nil, palette: []))
        doc.importLayer(imageData: gif(width: 4, height: 4, frames: 2), name: "Big")
        let layer = doc.activeLayer!
        XCTAssertNil(cel(doc, layer: layer.id, frame: 0), "(0, 0) is cropped away")
        XCTAssertNil(cel(doc, layer: layer.id, frame: 1), "(1, 0) is cropped away too: row 0 is outside")
    }

    func testUnreadableDataIsRefused() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        XCTAssertFalse(doc.importLayer(imageData: Data("nope".utf8), name: "X"))
        XCTAssertEqual(doc.sprite.layers.count, 1)
    }
}
