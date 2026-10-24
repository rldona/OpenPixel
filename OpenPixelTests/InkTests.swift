import XCTest
@testable import OpenPixel

final class InkMathTests: XCTestCase {
    private let red = PixelColor(r: 255, g: 0, b: 0)
    private let blue = PixelColor(r: 0, g: 0, b: 255)

    func testSimpleInkPaintsAndTransparentErases() {
        XCTAssertEqual(Ink.simple.apply(red, over: blue, alpha: 255), red)
        XCTAssertEqual(Ink.simple.apply(.clear, over: blue, alpha: 255), .clear)
        let half = Ink.simple.apply(.clear, over: blue, alpha: 128)
        XCTAssertEqual(half.b, 255)
        XCTAssertEqual(Int(half.a), 127, accuracy: 1)
    }

    func testAlphaCompositingNeverErases() {
        XCTAssertEqual(Ink.alphaCompositing.apply(.clear, over: blue, alpha: 255), blue)
        let mix = Ink.alphaCompositing.apply(red, over: blue, alpha: 128)
        XCTAssertEqual(mix.a, 255)
        XCTAssertEqual(Int(mix.r), 128, accuracy: 1)
    }

    func testCopyReplacesAlphaToo() {
        let glass = PixelColor(r: 255, g: 0, b: 0, a: 100)
        XCTAssertEqual(Ink.copyColor.apply(glass, over: blue, alpha: 255), glass)
        XCTAssertEqual(Ink.simple.apply(glass, over: blue, alpha: 255).a, 255, "simple blends instead")
    }

    func testLockAlphaKeepsTransparencyAndEmptyPixels() {
        XCTAssertEqual(Ink.lockAlpha.apply(red, over: .clear, alpha: 255), .clear)
        let ghost = PixelColor(r: 0, g: 0, b: 255, a: 90)
        XCTAssertEqual(Ink.lockAlpha.apply(red, over: ghost, alpha: 255), PixelColor(r: 255, g: 0, b: 0, a: 90))
    }

    func testShadingStepsAlongTheRamp() {
        let ramp = [PixelColor.black, PixelColor(r: 128, g: 128, b: 128), .white]
        func shade(_ c: PixelColor, _ d: ShadeDirection) -> PixelColor {
            Ink.shading.apply(red, over: c, alpha: 255) { d.step($0, in: ramp) }
        }
        XCTAssertEqual(shade(.black, .forward), ramp[1])
        XCTAssertEqual(shade(.white, .forward), .white, "stays at the end")
        XCTAssertEqual(shade(.white, .backward), ramp[1])
        XCTAssertEqual(shade(blue, .forward), blue, "colors outside the ramp are left alone")
        XCTAssertEqual(shade(.clear, .forward), .clear)
    }
}

@MainActor
final class InkDocumentTests: XCTestCase {
    private let ramp = [PixelColor.black, PixelColor(r: 85, g: 85, b: 85), PixelColor(r: 170, g: 170, b: 170), .white]

    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 8, background: nil, palette: ramp))
        doc.primary = .black
        return doc
    }

    private func pixel(_ doc: SpriteDocument, _ x: Int, _ y: Int) -> PixelColor {
        doc.sprite.cel(layer: doc.activeLayerID, frame: doc.activeFrame.id)?[x, y] ?? .clear
    }

    private func stroke(_ doc: SpriteDocument, _ points: [PixelPoint], pressures: [Double]? = nil) {
        doc.beginStroke(at: points[0], pressure: pressures?[0] ?? 1)
        if points.count > 1 {
            doc.continueStroke(through: Array(points.dropFirst()), pressures: pressures.map { Array($0.dropFirst()) })
        }
        doc.endStroke()
    }

    func testOpacityDoesNotBuildUpWithinAStroke() {
        let doc = makeDocument()
        doc.toolOpacity = 128
        // Back and forth over the same pixels.
        stroke(doc, [PixelPoint(x: 0, y: 0), PixelPoint(x: 3, y: 0), PixelPoint(x: 0, y: 0), PixelPoint(x: 3, y: 0)])
        XCTAssertEqual(pixel(doc, 1, 0).a, 128)
        // A second stroke does build up, as in Aseprite.
        stroke(doc, [PixelPoint(x: 1, y: 0)])
        XCTAssertGreaterThan(pixel(doc, 1, 0).a, 128)
    }

    func testShadingShadesOncePerStroke() {
        let doc = makeDocument()
        doc.primary = ramp[1]
        stroke(doc, [PixelPoint(x: 0, y: 0), PixelPoint(x: 4, y: 0)])
        doc.ink = .shading
        stroke(doc, [PixelPoint(x: 0, y: 0), PixelPoint(x: 4, y: 0), PixelPoint(x: 0, y: 0)])
        XCTAssertEqual(pixel(doc, 2, 0), ramp[2], "one step, even going over it twice")
        XCTAssertEqual(pixel(doc, 2, 1), .clear, "empty pixels aren't shaded")
        doc.shadeDirection = .backward
        stroke(doc, [PixelPoint(x: 2, y: 0)])
        stroke(doc, [PixelPoint(x: 2, y: 0)])
        XCTAssertEqual(pixel(doc, 2, 0), ramp[0])
    }

    func testLockAlphaOnlyRecolorsDrawnPixels() {
        let doc = makeDocument()
        stroke(doc, [PixelPoint(x: 2, y: 2)])
        doc.ink = .lockAlpha
        doc.primary = .white
        doc.setBrushSize(3)
        stroke(doc, [PixelPoint(x: 2, y: 2)])
        XCTAssertEqual(pixel(doc, 2, 2), .white)
        XCTAssertEqual(pixel(doc, 1, 1), .clear)
    }

    func testPressureScalesSizeAndOpacity() {
        let doc = makeDocument()
        doc.setBrushSize(5)
        doc.pressureSize = true
        defer { doc.pressureSize = false; doc.pressureOpacity = false }
        stroke(doc, [PixelPoint(x: 4, y: 4)], pressures: [0])
        XCTAssertEqual(pixel(doc, 4, 4), .black)
        XCTAssertEqual(pixel(doc, 3, 4), .clear, "no pressure: 1 px")
        stroke(doc, [PixelPoint(x: 4, y: 4)], pressures: [1])
        XCTAssertEqual(pixel(doc, 2, 4), .black, "full pressure: the whole brush")

        doc.undo(); doc.undo()
        doc.pressureSize = false
        doc.pressureOpacity = true
        doc.setBrushSize(1)
        stroke(doc, [PixelPoint(x: 0, y: 0)], pressures: [0.5])
        XCTAssertEqual(Int(pixel(doc, 0, 0).a), 128, accuracy: 1)
        stroke(doc, [PixelPoint(x: 0, y: 7)])
        XCTAssertEqual(pixel(doc, 0, 7).a, 255, "a finger stroke has full pressure")
    }

    func testBucketUsesInkAndOpacity() {
        let doc = makeDocument()
        doc.toolOpacity = 51
        doc.select(.bucket)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.endStroke()
        XCTAssertEqual(pixel(doc, 7, 7).a, 51)
        doc.toolOpacity = 255
        doc.undo()
        doc.select(.pencil)
        doc.ink = .simple
        stroke(doc, [PixelPoint(x: 0, y: 0), PixelPoint(x: 7, y: 0)])
        doc.select(.bucket)
        doc.ink = .shading
        doc.beginStroke(at: PixelPoint(x: 3, y: 0))
        doc.endStroke()
        XCTAssertEqual(pixel(doc, 7, 0), ramp[1])
        XCTAssertEqual(pixel(doc, 3, 3), .clear)
    }

    func testEraserOpacity() {
        let doc = makeDocument()
        stroke(doc, [PixelPoint(x: 0, y: 0)])
        doc.select(.eraser)
        doc.ink = .shading
        doc.toolOpacity = 128
        stroke(doc, [PixelPoint(x: 0, y: 0)])
        XCTAssertEqual(pixel(doc, 0, 0).r, 0, "the eraser ignores the ink")
        XCTAssertEqual(Int(pixel(doc, 0, 0).a), 127, accuracy: 1)
    }
}
