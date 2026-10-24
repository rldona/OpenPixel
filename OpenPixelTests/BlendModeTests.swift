import XCTest
@testable import OpenPixel

final class BlendModeMathTests: XCTestCase {
    private let gray = PixelColor(r: 128, g: 128, b: 128)
    private let red = PixelColor(r: 255, g: 0, b: 0)

    func testChannelFormulas() {
        XCTAssertEqual(BlendMode.multiply.channel(0.5, 0.5), 0.25)
        XCTAssertEqual(BlendMode.screen.channel(0.5, 0.5), 0.75)
        XCTAssertEqual(BlendMode.difference.channel(0.2, 0.7), 0.5, accuracy: 1e-9)
        XCTAssertEqual(BlendMode.addition.channel(0.7, 0.7), 1)
        XCTAssertEqual(BlendMode.subtract.channel(0.2, 0.7), 0)
        XCTAssertEqual(BlendMode.darken.channel(0.2, 0.7), 0.2)
        XCTAssertEqual(BlendMode.overlay.channel(0.25, 1), 0.5, accuracy: 1e-9)
        for mode in BlendMode.allCases {
            for b in stride(from: 0.0, through: 1, by: 0.25) {
                for s in stride(from: 0.0, through: 1, by: 0.25) {
                    let v = mode.channel(b, s)
                    XCTAssertTrue((0...1).contains(v), "\(mode) \(b) \(s) → \(v)")
                }
            }
        }
    }

    func testCompositeKeepsAlphaAndTransparentBackdrop() {
        let white = PixelColor.white
        XCTAssertEqual(BlendMode.multiply.composite(red, over: white, opacity: 1), red)
        XCTAssertEqual(BlendMode.multiply.composite(gray, over: .clear, opacity: 1), gray, "nothing under it: shows as is")
        let half = BlendMode.multiply.composite(PixelColor.black, over: white, opacity: 0.5)
        XCTAssertEqual(Int(half.r), 128, accuracy: 1)
        XCTAssertEqual(half.a, 255)
    }
}

@MainActor
final class BlendModeDocumentTests: XCTestCase {
    func testLayerBlendModeChangesTheCompositeAndMerge() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 2, height: 1, background: .white, palette: []))
        doc.addLayer()
        doc.primary = PixelColor(r: 128, g: 128, b: 128)
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.endStroke()
        doc.setBlendMode(.screen, layer: doc.activeLayerID)
        XCTAssertEqual(doc.sprite.layers[1].blendMode, .screen)
        XCTAssertEqual(doc.sprite.composite(frameIndex: 0)[0, 0], .white, "screen over white stays white")
        doc.setBlendMode(.multiply, layer: doc.activeLayerID)
        XCTAssertEqual(doc.sprite.composite(frameIndex: 0)[0, 0].r, 128)
        doc.mergeDown(doc.activeLayerID)
        XCTAssertEqual(doc.sprite.layers.count, 1)
        XCTAssertEqual(doc.sprite.cel(layer: doc.activeLayerID, frame: doc.activeFrame.id)?[0, 0].r, 128)
        doc.undo(); doc.undo()
        XCTAssertEqual(doc.sprite.layers[1].blendMode, .screen, "undoable")
        let data = try! JSONEncoder().encode(doc.sprite)
        XCTAssertEqual(try! JSONDecoder().decode(Sprite.self, from: data).layers[1].blendMode, .screen)
    }
}
