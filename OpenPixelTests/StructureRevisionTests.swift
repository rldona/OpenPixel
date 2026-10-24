import XCTest
@testable import OpenPixel

@MainActor
final class StructureRevisionTests: XCTestCase {
    /// Drawing on a cel that already has content changes pixels only, so the
    /// interface that reads `structure` (timeline, panels, bars) isn't rebuilt.
    func testStrokesOnAFilledCelDontChangeTheStructure() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 16, height: 16, background: nil, palette: []))
        doc.beginStroke(at: PixelPoint(x: 1, y: 1))
        doc.endStroke()
        let structure = doc.structureRevision, revision = doc.revision
        doc.beginStroke(at: PixelPoint(x: 2, y: 2))
        doc.continueStroke(to: PixelPoint(x: 8, y: 8))
        doc.endStroke()
        XCTAssertNotEqual(doc.revision, revision)
        XCTAssertEqual(doc.structureRevision, structure)
        doc.addLayer()
        XCTAssertNotEqual(doc.structureRevision, structure, "a new layer is structural")
    }

    func testNewCelsAndNewTilesAreStructural() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 8, background: nil, palette: []))
        var structure = doc.structureRevision
        doc.beginStroke(at: PixelPoint(x: 1, y: 1))
        doc.endStroke()
        XCTAssertNotEqual(doc.structureRevision, structure, "an empty cel got content: the timeline shows it")
        doc.setGrid(GridSettings(width: 4, height: 4))
        doc.addTilemapLayer()
        structure = doc.structureRevision
        doc.beginStroke(at: PixelPoint(x: 5, y: 5))
        doc.endStroke()
        XCTAssertNotEqual(doc.structureRevision, structure, "a new tile: the tileset panel shows it")
    }
}
