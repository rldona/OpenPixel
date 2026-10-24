import XCTest
@testable import OpenPixel

final class RasterTests: XCTestCase {
    func testLineIncludesBothEnds() {
        let points = Raster.line(from: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 4, y: 2))
        XCTAssertEqual(points.first, PixelPoint(x: 0, y: 0))
        XCTAssertEqual(points.last, PixelPoint(x: 4, y: 2))
        XCTAssertEqual(points.count, 5)
    }

    func testFloodFillStopsAtBorders() {
        var image = PixelImage(width: 5, height: 5)
        for y in 0..<5 { image[2, y] = .black }
        Raster.floodFill(&image, at: PixelPoint(x: 0, y: 0), with: .white)
        XCTAssertEqual(image[1, 4], .white)
        XCTAssertEqual(image[2, 2], .black)
        XCTAssertEqual(image[3, 0], .clear)
    }
}

final class SpriteTests: XCTestCase {
    private func twoLayerSprite() -> Sprite {
        var sprite = Sprite.blank(width: 2, height: 1, background: .white, palette: [])
        let top = Layer(name: "Arriba")
        sprite.layers.append(top)
        var image = PixelImage(width: 2, height: 1)
        image[0, 0] = PixelColor(r: 255, g: 0, b: 0)
        sprite.cels[CelKey(layer: top.id, frame: sprite.frames[0].id)] = image
        return sprite
    }

    func testCompositeStacksLayers() {
        let sprite = twoLayerSprite()
        let out = sprite.composite(frameIndex: 0)
        XCTAssertEqual(out[0, 0], PixelColor(r: 255, g: 0, b: 0))
        XCTAssertEqual(out[1, 0], .white)
    }

    func testHiddenLayerIsSkipped() {
        var sprite = twoLayerSprite()
        sprite.layers[1].isVisible = false
        XCTAssertEqual(sprite.composite(frameIndex: 0)[0, 0], .white)
    }

    func testLayerOpacityBlends() {
        var sprite = twoLayerSprite()
        sprite.layers[1].opacity = 0.5
        let p = sprite.composite(frameIndex: 0)[0, 0]
        XCTAssertEqual(p.r, 255)
        XCTAssertEqual(p.g, 128)
        XCTAssertEqual(p.a, 255)
    }

    func testCodableRoundTrip() throws {
        let file = SpriteFile(name: "Test", sprite: twoLayerSprite())
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(SpriteFile.self, from: data)
        XCTAssertEqual(decoded.sprite, file.sprite)
        XCTAssertEqual(decoded.name, "Test")
    }

    func testHexParsing() {
        XCTAssertEqual(PixelColor(hex: "#FF7A59"), PixelColor(r: 255, g: 122, b: 89))
        XCTAssertEqual(PixelColor(hex: "00000080")?.a, 128)
        XCTAssertNil(PixelColor(hex: "nope"))
        XCTAssertEqual(PixelColor(r: 1, g: 2, b: 3).hex, "#010203")
    }
}

@MainActor
final class SpriteDocumentTests: XCTestCase {
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 8, background: nil, palette: Palette.pico8.colors))
        doc.primary = .black
        return doc
    }

    private func pixel(_ doc: SpriteDocument, _ x: Int, _ y: Int) -> PixelColor {
        doc.sprite.composite(frameIndex: doc.activeFrameIndex)[x, y]
    }

    func testStrokeUndoRedo() {
        let doc = makeDocument()
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.continueStroke(to: PixelPoint(x: 3, y: 0))
        doc.endStroke()
        XCTAssertEqual(pixel(doc, 2, 0), .black)
        doc.undo()
        XCTAssertEqual(pixel(doc, 2, 0), .clear)
        doc.redo()
        XCTAssertEqual(pixel(doc, 2, 0), .black)
    }

    func testCancelledStrokeLeavesNoTrace() {
        let doc = makeDocument()
        doc.beginStroke(at: PixelPoint(x: 1, y: 1))
        doc.cancelStroke()
        XCTAssertEqual(pixel(doc, 1, 1), .clear)
        XCTAssertFalse(doc.canUndo)
    }

    func testMirrorPaintsBothSides() {
        let doc = makeDocument()
        doc.mirrorX = true
        doc.beginStroke(at: PixelPoint(x: 1, y: 2))
        doc.endStroke()
        XCTAssertEqual(pixel(doc, 6, 2), .black)
    }

    func testLockedLayerIsNotPainted() {
        let doc = makeDocument()
        doc.toggleLock(doc.activeLayerID)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.endStroke()
        XCTAssertEqual(pixel(doc, 0, 0), .clear)
        XCTAssertNotNil(doc.notice)
    }

    func testAddFrameDuplicatesCels() {
        let doc = makeDocument()
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.endStroke()
        doc.addFrame()
        XCTAssertEqual(doc.sprite.frames.count, 2)
        XCTAssertEqual(doc.activeFrameIndex, 1)
        XCTAssertEqual(pixel(doc, 0, 0), .black)
        doc.addFrame(empty: true)
        XCTAssertEqual(pixel(doc, 0, 0), .clear)
    }

    func testDeleteLayerRemovesItsCels() {
        let doc = makeDocument()
        doc.addLayer()
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.endStroke()
        doc.deleteLayer(doc.activeLayerID)
        XCTAssertEqual(doc.sprite.layers.count, 1)
        XCTAssertTrue(doc.sprite.cels.isEmpty)
    }

    func testBucketFill() {
        let doc = makeDocument()
        doc.select(.bucket)
        doc.beginStroke(at: PixelPoint(x: 4, y: 4))
        XCTAssertEqual(pixel(doc, 0, 7), .black)
        doc.undo()
        XCTAssertEqual(pixel(doc, 0, 7), .clear)
    }
}

final class ExporterTests: XCTestCase {
    func testSpriteSheetPlacesFramesSideBySide() {
        var sprite = Sprite.blank(width: 2, height: 2, background: nil, palette: [])
        let second = Frame()
        sprite.frames.append(second)
        var image = PixelImage(width: 2, height: 2)
        image[0, 0] = .white
        sprite.cels[CelKey(layer: sprite.layers[0].id, frame: second.id)] = image
        let sheet = Exporter.spriteSheet(sprite)
        XCTAssertEqual(sheet.width, 4)
        XCTAssertEqual(sheet[2, 0], .white)
        XCTAssertEqual(sheet[0, 0], .clear)
    }

    func testPNGAndGIFEncode() throws {
        var sprite = Sprite.blank(width: 4, height: 4, background: .white, palette: [])
        sprite.frames.append(Frame())
        XCTAssertFalse(try Exporter.pngData(sprite.composite(frameIndex: 0)).isEmpty)
        XCTAssertFalse(try Exporter.gifData(sprite, scale: 2).isEmpty)
    }

    func testCGImageRoundTrip() throws {
        var image = PixelImage(width: 2, height: 1)
        image[0, 0] = PixelColor(r: 10, g: 200, b: 30)
        let cg = try XCTUnwrap(image.makeCGImage())
        XCTAssertEqual(PixelImage(cgImage: cg), image)
    }
}
