import XCTest
@testable import OpenPixel

@MainActor
final class TilemapTests: XCTestCase {
    /// An 8 × 4 sprite with a 4 × 4 grid: two cells side by side.
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 4, background: nil, palette: []))
        doc.primary = .black
        doc.setGrid(GridSettings(width: 4, height: 4))
        doc.addTilemapLayer()
        return doc
    }

    private func dot(_ doc: SpriteDocument, _ x: Int, _ y: Int) {
        doc.beginStroke(at: PixelPoint(x: x, y: y))
        doc.endStroke()
    }

    private var key: (SpriteDocument) -> CelKey { { CelKey(layer: $0.activeLayerID, frame: $0.activeFrame.id) } }
    private func map(_ doc: SpriteDocument) -> [Int] { doc.sprite.tilemaps[key(doc)]?.tiles ?? [] }
    private func tileCount(_ doc: SpriteDocument) -> Int { doc.activeLayer?.tileset?.tiles.count ?? 0 }
    private func pixel(_ doc: SpriteDocument, _ x: Int, _ y: Int) -> PixelColor {
        doc.sprite.cel(layer: doc.activeLayerID, frame: doc.activeFrame.id)?[x, y] ?? .clear
    }

    func testAutoModeMakesReusesAndDropsTiles() {
        let doc = makeDocument()
        XCTAssertTrue(doc.activeLayer?.isTilemap == true)
        XCTAssertEqual(tileCount(doc), 1, "just the empty tile")
        dot(doc, 1, 1)
        XCTAssertEqual(map(doc), [1, 0])
        XCTAssertEqual(tileCount(doc), 2)
        dot(doc, 5, 1)
        XCTAssertEqual(map(doc), [1, 1], "the same drawing reuses the tile")
        XCTAssertEqual(tileCount(doc), 2)
        dot(doc, 6, 1)
        XCTAssertEqual(map(doc), [1, 2])
        doc.select(.eraser)
        dot(doc, 1, 1)
        XCTAssertEqual(map(doc), [0, 1], "the unused tile is dropped and the others renumbered")
        XCTAssertEqual(tileCount(doc), 2)
        doc.undo()
        XCTAssertEqual(map(doc), [1, 2])
    }

    func testManualModeEditsEveryCopyOfTheTile() {
        let doc = makeDocument()
        dot(doc, 1, 1)
        dot(doc, 5, 1)
        XCTAssertEqual(map(doc), [1, 1])
        doc.tilesetMode = .manual
        dot(doc, 2, 2)
        XCTAssertEqual(map(doc), [1, 1])
        XCTAssertEqual(pixel(doc, 6, 2), .black, "the other copy changed too")
        XCTAssertEqual(tileCount(doc), 2)
    }

    func testStackModeAlwaysAddsTiles() {
        let doc = makeDocument()
        doc.tilesetMode = .stack
        dot(doc, 1, 1)
        dot(doc, 5, 1)
        XCTAssertEqual(map(doc), [1, 2], "identical drawings still get their own tiles")
        XCTAssertEqual(tileCount(doc), 3)
    }

    func testTilesModePlacesFillsPicksAndErasesTiles() {
        let doc = makeDocument()
        dot(doc, 1, 1)
        doc.tileDrawMode = .tiles
        doc.selectedTile = 1
        dot(doc, 6, 2)
        XCTAssertEqual(map(doc), [1, 1])
        XCTAssertEqual(pixel(doc, 5, 1), .black, "the tile's pixels are drawn")
        doc.select(.eraser)
        dot(doc, 0, 0)
        XCTAssertEqual(map(doc), [0, 1])
        XCTAssertEqual(pixel(doc, 1, 1), .clear)
        doc.select(.bucket)
        dot(doc, 0, 0)
        XCTAssertEqual(map(doc), [1, 1])
        doc.selectedTile = 0
        doc.select(.eyedropper)
        dot(doc, 2, 2)
        XCTAssertEqual(doc.selectedTile, 1)
        doc.undo()
        XCTAssertEqual(map(doc), [0, 1], "one undo step per stroke")
    }

    func testConvertSaveAndBackToALayer() throws {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 4, background: nil, palette: []))
        doc.primary = .black
        doc.setGrid(GridSettings(width: 4, height: 4))
        dot(doc, 1, 1)
        dot(doc, 5, 1)
        doc.convertToTilemap(doc.activeLayerID)
        XCTAssertEqual(map(doc), [1, 1])
        XCTAssertEqual(tileCount(doc), 2)
        let decoded = try JSONDecoder().decode(Sprite.self, from: JSONEncoder().encode(doc.sprite))
        XCTAssertEqual(decoded.tilemaps, doc.sprite.tilemaps)
        XCTAssertEqual(decoded.layers[0].tileset, doc.sprite.layers[0].tileset)
        doc.convertToNormalLayer(doc.activeLayerID)
        XCTAssertFalse(doc.activeLayer?.isTilemap ?? true)
        XCTAssertTrue(doc.sprite.tilemaps.isEmpty)
        XCTAssertEqual(pixel(doc, 5, 1), .black, "pixels stay")
    }

    func testPartialCellsAtTheEdgeAndFrames() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 6, height: 4, background: nil, palette: []))
        doc.primary = .black
        doc.setGrid(GridSettings(width: 4, height: 4))
        doc.addTilemapLayer()
        dot(doc, 5, 3)
        XCTAssertEqual(map(doc), [0, 1], "the last column is half a tile")
        doc.addFrame()
        XCTAssertEqual(map(doc), [0, 1], "a duplicated frame gets the same tiles")
        let image = doc.sprite.tilesetImage(doc.activeLayer!.tileset!)
        XCTAssertEqual(image.width, 4)
        XCTAssertEqual(image[1, 3], .black)
    }
}
