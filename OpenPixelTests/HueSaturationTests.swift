import XCTest
@testable import OpenPixel

@MainActor
final class HueSaturationTests: XCTestCase {
    private let red = PixelColor(r: 255, g: 0, b: 0)

    func testHSLRoundTrip() {
        for color in [red, PixelColor(r: 12, g: 200, b: 99), PixelColor(r: 240, g: 240, b: 10), .white, .black] {
            XCTAssertEqual(PixelColor(hsl: color.hsl), color)
        }
    }

    func testAdjustmentMath() {
        XCTAssertEqual(HueSaturation(hue: 120).apply(red), PixelColor(r: 0, g: 255, b: 0), "hue turns")
        XCTAssertEqual(HueSaturation(saturation: -1).apply(red), PixelColor(r: 128, g: 128, b: 128), "no saturation is gray at the same lightness")
        XCTAssertEqual(HueSaturation(mode: .hsv, lightness: -0.5).apply(red), PixelColor(r: 128, g: 0, b: 0), "value halves")
        XCTAssertEqual(HueSaturation(mode: .hslAdd, lightness: 0.5).apply(red), .white, "+ modes add")
        XCTAssertEqual(HueSaturation(alpha: -0.5).apply(red).a, 127)
        XCTAssertEqual(HueSaturation(hue: 120, red: false).apply(red), PixelColor(r: 255, g: 255, b: 0), "red channel kept")
        XCTAssertEqual(HueSaturation(hue: 90).apply(.clear), .clear)
    }

    func testPreviewCancelAndApply() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        let key = CelKey(layer: doc.sprite.layers[0].id, frame: doc.sprite.frames[0].id)
        doc.primary = red
        doc.select(.pencil)
        doc.beginStroke(at: PixelPoint(x: 1, y: 1))
        doc.endStroke()
        XCTAssertEqual(doc.sprite.cels[key]?[1, 1], red)
        let original = doc.sprite

        doc.beginHueSaturation()
        XCTAssertTrue(doc.isAdjustingHueSaturation)
        doc.previewHueSaturation(HueSaturation(hue: 120), everyCel: false)
        XCTAssertEqual(doc.sprite.cels[key]?[1, 1], PixelColor(r: 0, g: 255, b: 0), "the canvas shows the preview")
        doc.endHueSaturation(apply: nil, everyCel: false)
        XCTAssertEqual(doc.sprite, original, "cancel puts the pixels back")
        XCTAssertFalse(doc.isAdjustingHueSaturation)

        doc.beginHueSaturation()
        doc.previewHueSaturation(HueSaturation(hue: 120), everyCel: false)
        doc.endHueSaturation(apply: HueSaturation(hue: 240), everyCel: false)
        XCTAssertEqual(doc.sprite.cels[key]?[1, 1], PixelColor(r: 0, g: 0, b: 255))
        doc.undo()
        XCTAssertEqual(doc.sprite, original, "applying is one undo step")
    }

    func testShadingRamps() {
        let base = PixelColor(r: 200, g: 80, b: 40)
        for ramp in [ColorShading.shades(base), ColorShading.lights(base), ColorShading.saturations(base), ColorShading.hues(base)] {
            XCTAssertEqual(ramp.count, 7)
            XCTAssertEqual(ramp[3], base, "the base sits in the middle")
        }
        let shades = ColorShading.shades(base)
        XCTAssertLessThan(shades[0].luminance, shades[2].luminance)
        XCTAssertLessThan(shades[4].luminance, shades[6].luminance)
        XCTAssertGreaterThan(shades[0].hsv.h, 200, "shadows lean blue")
        XCTAssertLessThan(ColorShading.saturations(base)[0].hsv.s, 0.01)
        XCTAssertEqual(ColorShading.rotate(350, towards: 10, by: 30), 10, "the short way round")
    }
}
