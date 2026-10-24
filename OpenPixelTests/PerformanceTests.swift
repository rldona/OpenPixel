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
}
