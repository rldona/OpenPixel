import XCTest
@testable import OpenPixel

final class PixelFontTests: XCTestCase {
    func testGlyphsAreWellFormed() {
        for font in PixelFont.all {
            for (character, glyph) in font.glyphs {
                XCTAssertFalse(glyph.rows.isEmpty, "\(font.name) \(character)")
                XCTAssertEqual(Set(glyph.rows.map(\.count)).count, 1, "\(font.name) \(character): rows of different widths")
                XCTAssertTrue(glyph.rows.joined().allSatisfy { $0 == "#" || $0 == "." }, "\(font.name) \(character)")
                XCTAssertTrue(glyph.rows.joined().contains("#"), "\(font.name) \(character) is empty")
            }
        }
    }

    func testFallbacks() {
        let tiny = PixelFont.tiny, standard = PixelFont.standard
        XCTAssertEqual(tiny.glyph(for: "a")?.rows, tiny.glyphs["A"]?.rows, "no lowercase: use capitals")
        XCTAssertEqual(tiny.glyph(for: "á")?.rows, tiny.glyphs["A"]?.rows, "no accents: plain letter")
        XCTAssertEqual(tiny.glyph(for: "ñ")?.rows, tiny.glyphs["Ñ"]?.rows)
        XCTAssertEqual(standard.glyph(for: "€")?.rows, standard.glyphs["?"]?.rows)
        XCTAssertNil(standard.glyph(for: " "))
        XCTAssertNotNil(standard.glyph(for: "ß"), "multi-letter case mapping doesn't crash")
    }
}

final class TextRendererTests: XCTestCase {
    private let ink = PixelColor.black
    private let edge = PixelColor.white

    private func render(_ text: String, _ change: (inout TextStyle) -> Void = { _ in }) -> PixelImage? {
        var style = TextStyle()
        change(&style)
        return TextRenderer.render(text, style: style, color: ink, outlineColor: edge)
    }

    func testPixelFontLaysOutGlyphsWithSpacing() throws {
        let image = try XCTUnwrap(render("HI"))
        XCTAssertEqual(image.width, 5 + 1 + 3)
        XCTAssertEqual(image.height, 7)
        XCTAssertEqual(image[0, 0], ink, "H's left stem")
        XCTAssertEqual(image[5, 0], .clear, "the gap between letters")
        XCTAssertEqual(image[6, 0], ink, "I's top bar")
    }

    func testScaleAccentsAndDescenders() throws {
        XCTAssertEqual(try XCTUnwrap(render("HI") { $0.scale = 3 }).width, 27)
        XCTAssertEqual(try XCTUnwrap(render("É")).height, 9, "the accent sits above the capital")
        XCTAssertEqual(try XCTUnwrap(render("ag")).height, 7, "g hangs 2 px below the baseline")
        XCTAssertEqual(try XCTUnwrap(render("Ñandú")).height, 9)
    }

    func testLinesAlignment() throws {
        let left = try XCTUnwrap(render("I\nHH"))
        XCTAssertEqual(left.width, 11)
        // Each line keeps room for descenders (2) and capital accents (2), so lines don't shift with their content.
        XCTAssertEqual(left.height, 7 + 2 + 1 + 2 + 7)
        XCTAssertEqual(left[0, 0], ink)
        let right = try XCTUnwrap(render("I\nHH") { $0.alignment = .right })
        XCTAssertEqual(right[0, 0], .clear)
        XCTAssertEqual(right[8, 0], ink, "the short line ends at the right edge")
    }

    func testOutline() throws {
        let image = try XCTUnwrap(render("I") { $0.outline = true })
        XCTAssertEqual(image.width, 3 + 2)
        XCTAssertEqual(image.height, 7 + 2)
        XCTAssertEqual(image[0, 0], edge, "corners touch diagonally")
        XCTAssertEqual(image[1, 1], ink)
        XCTAssertTrue(image.pixels.allSatisfy { $0 == ink || $0 == edge || $0 == .clear })
    }

    func testNothingVisible() {
        XCTAssertNil(render(""))
        XCTAssertNil(render("   "))
        XCTAssertNil(render("\n"))
    }

    func testSystemFontHasNoSmoothing() throws {
        let image = try XCTUnwrap(render("Ag") { $0.font = .system(""); $0.pointSize = 24 })
        XCTAssertGreaterThan(image.height, 10)
        XCTAssertTrue(image.pixels.allSatisfy { $0 == ink || $0 == .clear }, "every pixel fully on or off")
    }
}

@MainActor
final class TextToolDocumentTests: XCTestCase {
    func testTapTypePlaceAndApply() throws {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 16, height: 16, background: nil, palette: []))
        doc.primary = .black
        doc.select(.text)
        doc.beginStroke(at: PixelPoint(x: 2, y: 3))
        doc.endStroke()
        XCTAssertEqual(doc.textAnchor, PixelPoint(x: 2, y: 3))
        XCTAssertFalse(doc.canUndo, "tapping doesn't change pixels")

        XCTAssertTrue(doc.placeText("HI"))
        XCTAssertNil(doc.textAnchor)
        XCTAssertTrue(doc.isTransforming, "the text floats until applied")
        XCTAssertEqual(doc.tool, .move)
        doc.applyTransform()
        XCTAssertEqual(doc.tool, .text, "back to the text tool")
        let image = doc.sprite.composite(frameIndex: 0)
        XCTAssertEqual(image[2, 3], .black)
        XCTAssertEqual(image[1, 3], .clear)
        XCTAssertEqual(image[8, 3], .black, "I's top bar")
        doc.undo()
        XCTAssertTrue(doc.sprite.composite(frameIndex: 0).isEmpty)
    }

    func testLockedLayerGetsNoText() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 8, background: nil, palette: []))
        doc.toggleLock(doc.activeLayerID)
        doc.select(.text)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        XCTAssertNil(doc.textAnchor)
        XCTAssertNotNil(doc.notice)
    }
}
