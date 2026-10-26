import XCTest
@testable import OpenPixel

final class TiledModeModelTests: XCTestCase {
    func testWrapOnlyAlongTiledAxes() {
        XCTAssertEqual(TiledMode.both.wrap(PixelPoint(x: -1, y: 9), width: 8, height: 8), PixelPoint(x: 7, y: 1))
        XCTAssertEqual(TiledMode.horizontal.wrap(PixelPoint(x: -1, y: 9), width: 8, height: 8), PixelPoint(x: 7, y: 9))
        XCTAssertEqual(TiledMode.vertical.wrap(PixelPoint(x: -1, y: 9), width: 8, height: 8), PixelPoint(x: -1, y: 1))
        XCTAssertEqual(TiledMode.none.wrap(PixelPoint(x: -1, y: 9), width: 8, height: 8), PixelPoint(x: -1, y: 9))
    }
}

@MainActor
final class TiledModeDocumentTests: XCTestCase {
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 8, background: nil, palette: []))
        doc.primary = .black
        return doc
    }

    private func pixel(_ doc: SpriteDocument, _ x: Int, _ y: Int) -> PixelColor {
        doc.sprite.cel(layer: doc.activeLayerID, frame: doc.activeFrame.id)?[x, y] ?? .clear
    }

    func testStrokesWrapAroundTheEdges() {
        let doc = makeDocument()
        doc.tiledMode = .horizontal
        doc.beginStroke(at: PixelPoint(x: 6, y: 2))
        doc.continueStroke(to: PixelPoint(x: 9, y: 2))
        doc.endStroke()
        for x in [6, 7, 0, 1] { XCTAssertEqual(pixel(doc, x, 2), .black, "x \(x)") }
        XCTAssertEqual(pixel(doc, 3, 2), .clear)
    }

    func testBrushWrapsAndVerticalStaysClipped() {
        let doc = makeDocument()
        doc.tiledMode = .horizontal
        doc.setBrushSize(3)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.endStroke()
        XCTAssertEqual(pixel(doc, 7, 1), .black, "the left part of the brush wraps")
        XCTAssertEqual(pixel(doc, 7, 7), .clear, "no wrapping vertically")
    }

    func testBucketOnACopyFillsTheSprite() {
        let doc = makeDocument()
        doc.tiledMode = .both
        doc.select(.bucket)
        doc.beginStroke(at: PixelPoint(x: -3, y: 11))
        doc.endStroke()
        XCTAssertEqual(pixel(doc, 4, 4), .black)
    }
}

@MainActor
final class RepeatCanvasTests: XCTestCase {
    private func cel(_ doc: SpriteDocument, _ layer: Int = 0) -> PixelImage? {
        doc.sprite.cel(layer: doc.sprite.layers[layer].id, frame: doc.sprite.frames[0].id)
    }

    func testHorizontalTilingBecomesCopiesAcross() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 8, background: nil, palette: []))
        doc.primary = .black
        doc.beginStroke(at: PixelPoint(x: 1, y: 2))
        doc.endStroke()
        doc.tiledMode = .horizontal
        doc.repeatCanvas(copies: 3)
        XCTAssertEqual(doc.sprite.width, 24)
        XCTAssertEqual(doc.sprite.height, 8, "only the tiled axis grows")
        for x in [1, 9, 17] { XCTAssertEqual(cel(doc)?[x, 2], .black, "copy at \(x)") }
        XCTAssertEqual(doc.tiledMode, .none, "the repetition is in the drawing now")
        doc.undo()
        XCTAssertEqual(doc.sprite.width, 8, "one undo step")
    }

    func testBothAxes() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        doc.tiledMode = .both
        doc.repeatCanvas(copies: 2)
        XCTAssertEqual(doc.sprite.width, 8)
        XCTAssertEqual(doc.sprite.height, 8)
    }

    func testATilemapRepeatsItsCellsWithTheSameTiles() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 4, background: nil, palette: []))
        doc.setGrid(GridSettings(width: 4, height: 4))
        doc.primary = .black
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.endStroke()
        doc.convertToTilemap(doc.sprite.layers[0].id)
        let tiles = doc.sprite.layers[0].tileset?.tiles.count
        doc.tiledMode = .horizontal
        doc.repeatCanvas(copies: 2)
        XCTAssertEqual(doc.sprite.width, 16)
        XCTAssertEqual(doc.sprite.layers[0].tileset?.tiles.count, tiles, "no new tiles")
        XCTAssertEqual(cel(doc)?[8, 0], .black)
    }
}
