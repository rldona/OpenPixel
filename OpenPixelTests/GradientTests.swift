import XCTest
@testable import OpenPixel

final class GradientModelTests: XCTestCase {
    func testBayerMatricesUseEveryLevelOnce() {
        XCTAssertEqual(Raster.bayer(2), [[0, 2], [3, 1]])
        for n in [2, 4, 8] {
            XCTAssertEqual(Raster.bayer(n).flatMap { $0 }.sorted(), Array(0..<(n * n)))
        }
    }

    func testLinearAndRadialPositions() {
        let a = PixelPoint(x: 0, y: 0), b = PixelPoint(x: 10, y: 0)
        let linear = Gradient(from: .black, to: .white, a: a, b: b, shape: .linear, dither: .none)
        XCTAssertEqual(linear.position(of: PixelPoint(x: 5, y: 7)), 0.5, "only the distance along the drag counts")
        XCTAssertEqual(linear.position(of: PixelPoint(x: -3, y: 0)), 0)
        XCTAssertEqual(linear.position(of: PixelPoint(x: 30, y: 0)), 1)
        let radial = Gradient(from: .black, to: .white, a: a, b: b, shape: .radial, dither: .none)
        XCTAssertEqual(radial.position(of: PixelPoint(x: 0, y: 5)), 0.5)
        XCTAssertEqual(linear.color(at: PixelPoint(x: 5, y: 0)), PixelColor(r: 128, g: 128, b: 128))
    }

    func testDitherUsesOnlyTheTwoColors() {
        let g = Gradient(from: .black, to: .white, a: PixelPoint(x: 0, y: 0), b: PixelPoint(x: 15, y: 0), shape: .linear, dither: .bayer4)
        var whites = 0
        for x in 0..<16 {
            for y in 0..<4 {
                let c = g.color(at: PixelPoint(x: x, y: y))
                XCTAssertTrue(c == .black || c == .white)
                if c == .white { whites += 1 }
            }
        }
        XCTAssertEqual(Double(whites) / 64, 0.5, accuracy: 0.1, "about half way on average")
        XCTAssertEqual(g.color(at: PixelPoint(x: 0, y: 0)), .black)
        XCTAssertEqual(g.color(at: PixelPoint(x: 15, y: 3)), .white)
    }
}

@MainActor
final class GradientToolTests: XCTestCase {
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 8, background: nil, palette: []))
        doc.primary = .black
        doc.secondary = .white
        return doc
    }

    private func pixel(_ doc: SpriteDocument, _ x: Int, _ y: Int) -> PixelColor {
        doc.sprite.cel(layer: doc.activeLayerID, frame: doc.activeFrame.id)?[x, y] ?? .clear
    }

    func testDragFillsTheBucketAreaWithAGradient() {
        let doc = makeDocument()
        // A wall at x = 4 splits the canvas.
        doc.select(.line)
        doc.beginStroke(at: PixelPoint(x: 4, y: 0))
        doc.continueStroke(to: PixelPoint(x: 4, y: 7))
        doc.endStroke()
        doc.select(.gradient)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 1, y: 0))
        doc.continueStroke(to: PixelPoint(x: 3, y: 0))
        doc.endStroke()
        XCTAssertEqual(pixel(doc, 0, 5), .black)
        XCTAssertEqual(pixel(doc, 3, 5), .white)
        XCTAssertNotEqual(pixel(doc, 1, 5), .black, "blended in between")
        XCTAssertEqual(pixel(doc, 4, 2), .black, "the wall stays")
        XCTAssertEqual(pixel(doc, 6, 6), .clear, "the other side isn't reached")
        doc.undo()
        XCTAssertEqual(pixel(doc, 0, 5), .clear, "one undo step")
    }

    func testGradientInsideTheSelectionWithDither() {
        let doc = makeDocument()
        doc.select(.selectRectangle)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 7, y: 1))
        doc.endStroke()
        doc.select(.gradient)
        doc.gradientDither = .bayer2
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 7, y: 0))
        doc.endStroke()
        XCTAssertEqual(pixel(doc, 3, 3), .clear)
        for x in 0..<8 { XCTAssertTrue([PixelColor.black, .white].contains(pixel(doc, x, 1))) }
    }
}
