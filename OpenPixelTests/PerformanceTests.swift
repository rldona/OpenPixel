import XCTest
@testable import OpenPixel

/// Timings of the work done per Pencil event on a 256×256 sprite.
/// Run with `-only-testing:OpenPixelTests/PerformanceTests` and read the output.
@MainActor
final class PerformanceTests: XCTestCase {
    private func time(_ label: String, _ n: Int = 100, _ body: () -> Void) -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<n { body() }
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000 / Double(n)
        print("PERF \(label): \(String(format: "%.3f", ms)) ms")
        return ms
    }

    func testPerEventCostOnLargeSprite() {
        let sprite = Sprite.blank(width: 256, height: 256, background: .white, palette: Palette.pico8.colors)
        let doc = SpriteDocument(name: "Big", sprite: sprite)
        doc.addLayer()
        var buffer = [PixelColor](repeating: .clear, count: 256 * 256)
        var dirtyAreas: [PixelRect] = []
        doc.onCanvasChange = { dirtyAreas.append($0) }

        doc.beginStroke(at: PixelPoint(x: 10, y: 10))
        // A zigzag that moves one pixel per sample, like a real stroke.
        var k = 0
        func next() -> PixelPoint {
            k += 1
            let bounce = k % 400 < 200 ? k % 200 : 199 - k % 200
            return PixelPoint(x: 20 + bounce, y: 20 + bounce / 2)
        }
        _ = time("stroke batch (4 samples)") {
            doc.continueStroke(through: (0..<4).map { _ in next() })
        }
        _ = time("recomposite dirty area") {
            doc.sprite.composite(frameIndex: 0, into: &buffer, rect: dirtyAreas.last!)
        }
        _ = time("CGImage from buffer") { _ = PixelImage.makeCGImage(pixels: buffer, width: 256, height: 256) }
        _ = time("full recomposite (stroke end)") {
            doc.sprite.composite(frameIndex: 0, into: &buffer, rect: .full(width: 256, height: 256))
        }
        doc.endStroke()
        XCTAssertTrue(dirtyAreas.allSatisfy { ($0.maxX - $0.minX) < 16 }, "a stroke batch should only dirty a small area")
    }

    /// What the newer interface adds per committed stroke on a big sprite: the
    /// stroke's end (undo snapshot, recent colors, structure check), a layer
    /// thumbnail for every layer and the onion skin marks for every frame.
    func testInterfaceCostOnLargeSpriteWithManyLayers() {
        var sprite = Sprite.blank(width: 256, height: 256, background: nil, palette: Palette.pico8.colors)
        for _ in 1..<24 { sprite.insertFrame(Frame(), at: sprite.frames.count) }
        let doc = SpriteDocument(name: "Big", sprite: sprite)
        for _ in 1..<20 { doc.addLayer() }
        // Something drawn on every layer, so thumbnails have content to crop.
        for (i, layer) in doc.sprite.layers.enumerated() {
            doc.activeLayerID = layer.id
            doc.beginStroke(at: PixelPoint(x: 10 + i * 10, y: 10))
            doc.continueStroke(through: (0..<60).map { PixelPoint(x: 10 + i * 10 + $0 / 4, y: 10 + $0 * 3) })
            doc.endStroke()
        }
        doc.onionSkin = true

        var k = 0
        let strokeEnd = time("stroke end on 20×24 cels (undo, recents, structure)", 20) {
            k += 1
            doc.primary = PixelColor(r: UInt8(k % 255), g: 40, b: 40)
            doc.beginStroke(at: PixelPoint(x: 100, y: 100 + k % 50))
            doc.continueStroke(through: [PixelPoint(x: 140, y: 100 + k % 50)])
            doc.endStroke()
        }
        let thumbnails = time("20 layer thumbnails (crop + CGImage), all redrawn", 20) {
            for layer in doc.sprite.layers {
                guard let cel = doc.sprite.cel(layer: layer.id, frame: doc.sprite.frames[0].id),
                      let bounds = SelectionMask.opaquePixels(of: cel).bounds else { continue }
                _ = cel.cropped(to: bounds).makeCGImage()
            }
        }
        let unchanged = time("20 thumbnails, cels unchanged (cache check)", 200) {
            let cels = doc.sprite.layers.compactMap { doc.sprite.cel(layer: $0.id, frame: doc.sprite.frames[0].id) }
            for cel in cels { _ = cel == cel }
        }
        let onion = time("onion marks for 24 frames", 1000) {
            for i in 0..<24 { _ = doc.onionOffset(of: i) }
        }
        XCTAssertEqual(doc.recentColors.count, SpriteDocument.recentColorCount)
        // Generous bounds for a Debug build on CI; Release is far faster.
        XCTAssertLessThan(strokeEnd, 250)
        XCTAssertLessThan(thumbnails, 250)
        XCTAssertLessThan(unchanged, 5)
        XCTAssertLessThan(onion, 1)
    }
}
