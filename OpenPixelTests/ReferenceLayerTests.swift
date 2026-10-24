import XCTest
import UIKit
@testable import OpenPixel

@MainActor
final class ReferenceLayerTests: XCTestCase {
    /// A 200 × 100 red picture.
    private var photo: Data {
        UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100), format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f
        }()).pngData { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 100))
        }
    }

    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 20, height: 20, background: nil, palette: []))
        doc.primary = .black
        return doc
    }

    func testAddedFittedAndHalfTransparent() throws {
        let doc = makeDocument()
        XCTAssertTrue(doc.addReferenceLayer(imageData: photo))
        let layer = try XCTUnwrap(doc.activeLayer)
        XCTAssertTrue(layer.isReference)
        XCTAssertEqual(layer.opacity, 0.5)
        XCTAssertEqual(layer.reference?.frame, CGRect(x: 0, y: 5, width: 20, height: 10), "fitted and centred")
        XCTAssertEqual(doc.sprite.layers.first?.id, layer.id, "under the drawing layer")
        doc.fitReference(layer.id, fill: true)
        XCTAssertEqual(doc.activeLayer?.reference?.frame, CGRect(x: -10, y: 0, width: 40, height: 20))
        doc.scaleReference(layer.id, by: 0.5)
        XCTAssertEqual(doc.activeLayer?.reference?.frame, CGRect(x: 0, y: 5, width: 20, height: 10))
        XCTAssertFalse(doc.addReferenceLayer(imageData: Data([1, 2, 3])))
        XCTAssertNotNil(doc.notice)
    }

    func testNotDrawnOnAndNotInTheImage() throws {
        let doc = makeDocument()
        doc.addReferenceLayer(imageData: photo)
        doc.beginStroke(at: PixelPoint(x: 5, y: 5))
        doc.endStroke()
        XCTAssertTrue(doc.sprite.cels.isEmpty, "can't draw on it")
        XCTAssertNotNil(doc.notice)
        XCTAssertTrue(doc.sprite.composite(frameIndex: 0).isEmpty, "not part of the image or exports")
    }

    func testMoveToolMovesItInOneUndoStep() throws {
        let doc = makeDocument()
        doc.addReferenceLayer(imageData: photo)
        doc.select(.move)
        doc.beginTransformDrag(.move, at: CGPoint(x: 5, y: 5))
        doc.continueTransformDrag(to: CGPoint(x: 8, y: 3))
        doc.endTransformDrag()
        XCTAssertFalse(doc.isTransforming)
        XCTAssertEqual(doc.activeLayer?.reference?.frame.origin, CGPoint(x: 3, y: 3))
        doc.undo()
        XCTAssertEqual(doc.activeLayer?.reference?.frame.origin, CGPoint(x: 0, y: 5))
    }

    func testSavedAndKeptWhenFlattening() throws {
        let doc = makeDocument()
        doc.beginStroke(at: PixelPoint(x: 1, y: 1))
        doc.endStroke()
        doc.addReferenceLayer(imageData: photo)
        let data = try JSONEncoder().encode(doc.sprite)
        let decoded = try JSONDecoder().decode(Sprite.self, from: data)
        XCTAssertEqual(decoded.layers.first?.reference, doc.sprite.layers.first?.reference)
        doc.flatten()
        XCTAssertEqual(doc.sprite.layers.filter(\.isReference).count, 1)
        XCTAssertEqual(doc.sprite.layers.count, 2)
    }
}
