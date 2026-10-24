import XCTest
@testable import OpenPixel

final class ColorMathTests: XCTestCase {
    func testHSVRoundTrip() {
        for hex in ["#FF004D", "#29ADFF", "#000000", "#FFFFFF", "#7E2553", "#00E436", "#808080"] {
            let color = PixelColor(hex: hex)!
            XCTAssertEqual(PixelColor(hsv: color.hsv), color, hex)
        }
        let red = PixelColor(r: 255, g: 0, b: 0).hsv
        XCTAssertEqual(red.h, 0)
        XCTAssertEqual(red.s, 1)
        XCTAssertEqual(PixelColor(r: 0, g: 0, b: 255).hsv.h, 240, accuracy: 0.001)
    }

    func testToleranceMatching() {
        let base = PixelColor(r: 100, g: 100, b: 100)
        XCTAssertTrue(base.matches(base, tolerance: 0))
        XCTAssertFalse(PixelColor(r: 101, g: 100, b: 100).matches(base, tolerance: 0))
        XCTAssertTrue(PixelColor(r: 110, g: 95, b: 100).matches(base, tolerance: 10))
        XCTAssertTrue(PixelColor(r: 9, g: 9, b: 9, a: 0).matches(.clear, tolerance: 0), "transparent matches transparent")
    }

    func testHarmoniesRotateTheHue() {
        let red = PixelColor(r: 255, g: 0, b: 0)
        XCTAssertEqual(ColorHarmony.complementary.colors(for: red), [red, PixelColor(r: 0, g: 255, b: 255)])
        XCTAssertEqual(ColorHarmony.triadic.colors(for: red).map(\.hex), ["#FF0000", "#00FF00", "#0000FF"])
        XCTAssertEqual(red.shadesAndTints.count, 7)
        XCTAssertEqual(red.shadesAndTints[3], red)
    }
}

final class PaletteTests: XCTestCase {
    private let ramp: [PixelColor] = ["#000000", "#111111", "#222222", "#FFFFFF"].compactMap(PixelColor.init(hex:))

    func testGradientFillsBetweenTheEnds() {
        var colors = ramp
        PaletteEditing.gradient(&colors, 0...3)
        XCTAssertEqual(colors.map(\.hex), ["#000000", "#555555", "#AAAAAA", "#FFFFFF"])
    }

    func testSortReverseAndMove() {
        var colors: [PixelColor] = ["#0000FF", "#FF0000", "#808080", "#00FF00"].compactMap(PixelColor.init(hex:))
        PaletteEditing.sort(&colors, 0...3, by: .hue)
        XCTAssertEqual(colors.map(\.hex), ["#808080", "#FF0000", "#00FF00", "#0000FF"], "grays first, then by hue")
        PaletteEditing.reverse(&colors, 1...3)
        XCTAssertEqual(colors.map(\.hex), ["#808080", "#0000FF", "#00FF00", "#FF0000"])
        let placed = PaletteEditing.move(&colors, 0...1, to: 3)
        XCTAssertEqual(colors.map(\.hex), ["#00FF00", "#FF0000", "#808080", "#0000FF"])
        XCTAssertEqual(placed, 2...3)
    }

    func testParsesCommonPaletteFiles() {
        let gpl = "GIMP Palette\nName: Test\nColumns: 4\n#\n255   0   0\tRed\n  0 255   0 Green\n"
        XCTAssertEqual(PaletteFile.parse(gpl).map(\.hex), ["#FF0000", "#00FF00"])
        let jasc = "JASC-PAL\n0100\n2\n0 0 255\n255 255 255\n"
        XCTAssertEqual(PaletteFile.parse(jasc).map(\.hex), ["#0000FF", "#FFFFFF"])
        let hex = "ff004d\n29adff\n"
        XCTAssertEqual(PaletteFile.parse(hex).map(\.hex), ["#FF004D", "#29ADFF"])
        let paintNet = "; paint.net palette\nFFFF004D\n8029ADFF\n"
        XCTAssertEqual(PaletteFile.parse(paintNet).map(\.hex), ["#FF004D", "#29ADFF80"], "AARRGGBB")
    }

    func testExportedFilesReadBack() {
        let colors = Palette.pico8.colors
        for format in PaletteFile.Format.allCases {
            let data = PaletteFile.data(colors, name: "Test", format: format)
            XCTAssertEqual(PaletteFile.colors(from: data, fileExtension: format.rawValue), colors, format.rawValue)
        }
        XCTAssertNil(PaletteFile.colors(from: Data("nothing here".utf8), fileExtension: "txt"))
    }

    func testPresetsAreComplete() {
        XCTAssertEqual(Palette.db32.colors.count, 32)
        XCTAssertEqual(Palette.endesga32.colors.count, 32)
        XCTAssertEqual(Palette.gameBoy.colors.count, 4)
        XCTAssertEqual(Set(Palette.presets.map(\.name)).count, Palette.presets.count)
    }
}

@MainActor
final class PaletteDocumentTests: XCTestCase {
    private let red = PixelColor(r: 255, g: 0, b: 0)
    private let blue = PixelColor(r: 0, g: 0, b: 255)

    /// 2 layers, 2 frames; every cel has a red pixel at (0, 0) and a near-red one at (1, 0).
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 4, height: 4, background: nil, palette: Palette.pico8.colors))
        doc.addLayer()
        doc.addFrame(empty: true)
        for layer in doc.sprite.layers {
            for frameIndex in 0..<2 {
                doc.selectCel(layer: layer.id, frameIndex: frameIndex)
                doc.primary = red
                doc.beginStroke(at: PixelPoint(x: 0, y: 0))
                doc.endStroke()
                doc.primary = PixelColor(r: 250, g: 5, b: 0)
                doc.beginStroke(at: PixelPoint(x: 1, y: 0))
                doc.endStroke()
            }
        }
        return doc
    }

    private func pixels(_ doc: SpriteDocument, _ x: Int, _ y: Int) -> [PixelColor] {
        doc.sprite.cels.values.map { $0[x, y] }
    }

    func testReplaceColorInTheActiveCel() {
        let doc = makeDocument()
        let changed = doc.replaceColor(red, with: blue, tolerance: 0, everyCel: false)
        XCTAssertEqual(changed, 1)
        XCTAssertEqual(pixels(doc, 0, 0).filter { $0 == blue }.count, 1)
        doc.undo()
        XCTAssertFalse(pixels(doc, 0, 0).contains(blue))
    }

    func testReplaceColorEverywhereWithTolerance() {
        let doc = makeDocument()
        doc.toggleLock(doc.sprite.layers[0].id)
        let changed = doc.replaceColor(red, with: blue, tolerance: 10, everyCel: true)
        XCTAssertEqual(changed, 4, "2 pixels × 2 frames on the unlocked layer")
        let bottom = doc.sprite.layers[0].id
        let lockedCels = doc.sprite.cels.filter { $0.key.layer == bottom }.values
        XCTAssertTrue(lockedCels.allSatisfy { $0[0, 0] == red }, "locked layers are left alone")
    }

    func testReplaceColorStaysInsideTheSelection() {
        let doc = makeDocument()
        doc.select(.selectRectangle)
        doc.beginStroke(at: PixelPoint(x: 1, y: 0))
        doc.continueStroke(to: PixelPoint(x: 2, y: 1))
        doc.endStroke()
        XCTAssertTrue(doc.hasSelection)
        doc.replaceColor(red, with: blue, tolerance: 10, everyCel: false)
        let cel = doc.sprite.cels[CelKey(layer: doc.activeLayerID, frame: doc.activeFrame.id)]!
        XCTAssertEqual(cel[0, 0], red)
        XCTAssertEqual(cel[1, 0], blue)
    }

    func testPaletteFromSpriteAndUndo() {
        let doc = makeDocument()
        doc.paletteFromSprite()
        XCTAssertEqual(doc.sprite.palette, [red, PixelColor(r: 250, g: 5, b: 0)])
        doc.undo()
        XCTAssertEqual(doc.sprite.palette, Palette.pico8.colors)
    }

    func testPaletteEditsAreUndoableAndKeepOneColor() {
        let doc = makeDocument()
        doc.removePaletteColors(0...15)
        XCTAssertEqual(doc.sprite.palette.count, 16)
        XCTAssertNotNil(doc.notice)
        doc.duplicatePaletteColors(0...1)
        XCTAssertEqual(Array(doc.sprite.palette.prefix(4)), [Palette.pico8.colors[0], Palette.pico8.colors[1], Palette.pico8.colors[0], Palette.pico8.colors[1]])
        doc.setPaletteColor(blue, at: 0)
        XCTAssertEqual(doc.paletteIndex(of: blue), 0)
        doc.undo()
        doc.undo()
        XCTAssertEqual(doc.sprite.palette, Palette.pico8.colors)
    }
}
