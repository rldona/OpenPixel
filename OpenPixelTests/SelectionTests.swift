import XCTest
@testable import OpenPixel

final class SelectionMaskTests: XCTestCase {
    func testRectAndModes() {
        let a = SelectionMask.rect(PixelRect(minX: 0, minY: 0, maxX: 3, maxY: 3), width: 8, height: 8)
        let b = SelectionMask.rect(PixelRect(minX: 2, minY: 2, maxX: 5, maxY: 5), width: 8, height: 8)
        XCTAssertEqual(a.combined(with: b, mode: .add).bits.filter { $0 }.count, 16 + 16 - 4)
        XCTAssertEqual(a.combined(with: b, mode: .subtract).bits.filter { $0 }.count, 12)
        XCTAssertEqual(a.combined(with: b, mode: .intersect).bounds, PixelRect(minX: 2, minY: 2, maxX: 3, maxY: 3))
        XCTAssertEqual(a.combined(with: b, mode: .replace), b)
    }

    func testRectIsClippedToCanvas() {
        let mask = SelectionMask.rect(PixelRect(minX: -5, minY: 6, maxX: 2, maxY: 20), width: 8, height: 8)
        XCTAssertEqual(mask.bounds, PixelRect(minX: 0, minY: 6, maxX: 2, maxY: 7))
    }

    func testPolygonFillsInside() {
        let triangle = [PixelPoint(x: 0, y: 0), PixelPoint(x: 9, y: 0), PixelPoint(x: 0, y: 9)]
        let mask = SelectionMask.polygon(triangle, width: 10, height: 10)
        XCTAssertTrue(mask.contains(PixelPoint(x: 2, y: 2)))
        XCTAssertTrue(mask.contains(PixelPoint(x: 9, y: 0)))
        XCTAssertFalse(mask.contains(PixelPoint(x: 8, y: 8)))
    }

    func testMagicWand() {
        var image = PixelImage(width: 4, height: 1)
        image[0, 0] = PixelColor(r: 100, g: 0, b: 0)
        image[1, 0] = PixelColor(r: 110, g: 0, b: 0)
        image[3, 0] = PixelColor(r: 100, g: 0, b: 0)
        let exact = SelectionMask.magicWand(in: image, at: PixelPoint(x: 0, y: 0), tolerance: 0, contiguous: true)
        XCTAssertEqual(exact.bits, [true, false, false, false])
        let tolerant = SelectionMask.magicWand(in: image, at: PixelPoint(x: 0, y: 0), tolerance: 16, contiguous: true)
        XCTAssertEqual(tolerant.bits, [true, true, false, false])
        let global = SelectionMask.magicWand(in: image, at: PixelPoint(x: 0, y: 0), tolerance: 16, contiguous: false)
        XCTAssertEqual(global.bits, [true, true, false, true])
    }

    func testExpandContractBorder() {
        let mask = SelectionMask.rect(PixelRect(minX: 3, minY: 3, maxX: 6, maxY: 6), width: 10, height: 10)
        XCTAssertEqual(mask.expanded(by: 1).bounds, PixelRect(minX: 2, minY: 2, maxX: 7, maxY: 7))
        XCTAssertEqual(mask.contracted(by: 1).bounds, PixelRect(minX: 4, minY: 4, maxX: 5, maxY: 5))
        let border = mask.border(1)
        XCTAssertTrue(border.contains(PixelPoint(x: 3, y: 3)))
        XCTAssertFalse(border.contains(PixelPoint(x: 4, y: 4)))
        // The canvas edge isn't a selection edge.
        XCTAssertEqual(SelectionMask(width: 4, height: 4, filled: true).contracted(by: 1).bits.filter { $0 }.count, 16)
    }

    func testOutlineMergesRuns() {
        let mask = SelectionMask.rect(PixelRect(minX: 1, minY: 1, maxX: 4, maxY: 2), width: 8, height: 8)
        XCTAssertEqual(mask.outline().count, 4)
    }
}

final class TransformTests: XCTestCase {
    private func source() -> PixelImage {
        var image = PixelImage(width: 3, height: 2)
        image[0, 0] = .black
        image[2, 1] = .white
        return image
    }

    private func render(_ f: inout FloatingSelection) -> PixelImage {
        let r = f.render(spriteWidth: 10, spriteHeight: 10)
        var canvas = PixelImage(width: 10, height: 10)
        canvas.paste(r.image, at: r.origin.x, r.origin.y)
        return canvas
    }

    private func floating() -> FloatingSelection {
        let image = source()
        return FloatingSelection(celKey: CelKey(layer: UUID(), frame: UUID()), source: image, sourceMask: SelectionMask(width: 3, height: 2, filled: true), at: PixelPoint(x: 2, y: 2))
    }

    func testIdentityRenderKeepsPixels() {
        var f = floating()
        let canvas = render(&f)
        XCTAssertEqual(canvas[2, 2], .black)
        XCTAssertEqual(canvas[4, 3], .white)
    }

    func testMoveFlipAndRotate90AreExact() {
        var f = floating()
        f.box.translate(dx: 3, dy: 1)
        var canvas = render(&f)
        XCTAssertEqual(canvas[5, 3], .black)

        f = floating()
        f.flip(horizontal: true)
        canvas = render(&f)
        XCTAssertEqual(canvas[4, 2], .black)
        XCTAssertEqual(canvas[2, 3], .white)

        f = floating()
        f.rotate90(clockwise: true)
        XCTAssertEqual(f.source.width, 2)
        XCTAssertEqual(f.box.width, 2)
        XCTAssertEqual(f.box.height, 3)
        canvas = render(&f)
        let painted = canvas.pixels.filter { !$0.isTransparent }
        XCTAssertEqual(painted.count, 2, "a 90° turn must not duplicate or drop pixels")
    }

    func testScaleHandleDoublesSize() {
        var f = floating()
        f.box.drag(handle: 4, to: CGPoint(x: 8, y: 6), keepAspect: false, aspect: f.aspect)
        XCTAssertEqual(f.box.width, 6)
        XCTAssertEqual(f.box.height, 4)
        let canvas = render(&f)
        XCTAssertEqual(canvas[2, 2], .black)
        XCTAssertEqual(canvas[3, 3], .black)
        XCTAssertEqual(canvas[7, 5], .white)
    }

    func testDraggingPastTheOppositeEdgeFlips() {
        var f = floating()
        f.box.drag(handle: 3, to: CGPoint(x: 0, y: 3), keepAspect: false, aspect: f.aspect)
        XCTAssertLessThan(f.box.x1, f.box.x0)
    }

    func testPivotChangeDoesNotMoveContent() {
        var f = floating()
        f.box.angle = .pi / 5
        let before = f.box.corners
        f.box.setPivot(CGPoint(x: 0, y: 0))
        for (a, b) in zip(before, f.box.corners) {
            XCTAssertEqual(a.x, b.x, accuracy: 1e-9)
            XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
        }
    }

    func testRotSpriteAndFastBothRender() {
        for algorithm in RotationAlgorithm.allCases {
            let solid = PixelImage(width: 3, height: 2, fill: .black)
            var f = FloatingSelection(celKey: CelKey(layer: UUID(), frame: UUID()), source: solid, sourceMask: SelectionMask(width: 3, height: 2, filled: true), at: PixelPoint(x: 2, y: 2))
            f.algorithm = algorithm
            f.box.angle = .pi / 4
            let canvas = render(&f)
            XCTAssertFalse(canvas.isEmpty, "\(algorithm) rendered nothing")
        }
    }

    func testScale2xKeepsDiagonalsSmooth() {
        var image = PixelImage(width: 2, height: 2)
        image[0, 0] = .black
        image[1, 1] = .black
        let up = image.scale2x()
        XCTAssertEqual(up.width, 4)
        XCTAssertEqual(up[1, 0], .black, "EPX fills the inner corner of a diagonal")
    }

    func testCanvasCropRotateFlip() {
        var sprite = Sprite.blank(width: 4, height: 2, background: nil, palette: [])
        var image = PixelImage(width: 4, height: 2)
        image[3, 0] = .black
        sprite.cels[CelKey(layer: sprite.layers[0].id, frame: sprite.frames[0].id)] = image
        XCTAssertEqual(sprite.contentBounds, PixelRect(minX: 3, minY: 0, maxX: 3, maxY: 0))
        var rotated = sprite
        rotated.rotateCanvas(clockwise: true)
        XCTAssertEqual([rotated.width, rotated.height], [2, 4])
        XCTAssertEqual(rotated.composite(frameIndex: 0)[1, 3], .black)
        var flipped = sprite
        flipped.flipCanvas(horizontal: true)
        XCTAssertEqual(flipped.composite(frameIndex: 0)[0, 0], .black)
        var cropped = sprite
        cropped.crop(to: sprite.contentBounds!)
        XCTAssertEqual([cropped.width, cropped.height], [1, 1])
        XCTAssertEqual(cropped.composite(frameIndex: 0)[0, 0], .black)
    }
}

@MainActor
final class SelectionDocumentTests: XCTestCase {
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 8, background: nil, palette: []))
        doc.primary = .black
        return doc
    }

    private func pixel(_ doc: SpriteDocument, _ x: Int, _ y: Int) -> PixelColor {
        doc.sprite.composite(frameIndex: doc.activeFrameIndex)[x, y]
    }

    private func select(_ doc: SpriteDocument, _ tool: Tool, from a: PixelPoint, to b: PixelPoint) {
        doc.select(tool)
        doc.beginStroke(at: a)
        doc.continueStroke(to: b)
        doc.endStroke()
    }

    func testMarqueeSelectsAndUndoes() {
        let doc = makeDocument()
        select(doc, .selectRectangle, from: PixelPoint(x: 1, y: 1), to: PixelPoint(x: 3, y: 3))
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 1, minY: 1, maxX: 3, maxY: 3))
        XCTAssertTrue(doc.hasSelection)
        doc.undo()
        XCTAssertNil(doc.selection)
        doc.redo()
        XCTAssertNotNil(doc.selection)
    }

    func testAddModeAndTapToDeselect() {
        let doc = makeDocument()
        select(doc, .selectRectangle, from: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 1, y: 1))
        doc.selectionMode = .add
        select(doc, .selectRectangle, from: PixelPoint(x: 5, y: 5), to: PixelPoint(x: 6, y: 6))
        XCTAssertEqual(doc.selection?.bits.filter { $0 }.count, 8)
        doc.selectionMode = .replace
        doc.beginStroke(at: PixelPoint(x: 4, y: 4))
        doc.endStroke()
        XCTAssertNil(doc.selection)
        doc.reselect()
        XCTAssertEqual(doc.selection?.bits.filter { $0 }.count, 8)
    }

    func testPaintingIsLimitedToSelection() {
        let doc = makeDocument()
        select(doc, .selectRectangle, from: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 3, y: 7))
        doc.select(.pencil)
        doc.beginStroke(at: PixelPoint(x: 0, y: 2))
        doc.continueStroke(to: PixelPoint(x: 7, y: 2))
        doc.endStroke()
        XCTAssertEqual(pixel(doc, 3, 2), .black)
        XCTAssertEqual(pixel(doc, 4, 2), .clear)
        doc.select(.bucket)
        doc.primary = .white
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        XCTAssertEqual(pixel(doc, 3, 0), .white)
        XCTAssertEqual(pixel(doc, 4, 0), .clear, "the fill stops at the selection edge")
    }

    func testMoveCommitAndUndoInOneStep() {
        let doc = makeDocument()
        doc.beginStroke(at: PixelPoint(x: 1, y: 1))
        doc.endStroke()
        select(doc, .selectRectangle, from: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 2, y: 2))
        doc.beginTransformDrag(.move, at: CGPoint(x: 1.5, y: 1.5))
        doc.continueTransformDrag(to: CGPoint(x: 4.5, y: 3.5))
        doc.endTransformDrag()
        XCTAssertTrue(doc.isTransforming)
        XCTAssertEqual(pixel(doc, 4, 3), .black)
        XCTAssertEqual(pixel(doc, 1, 1), .clear)
        doc.applyTransform()
        XCTAssertFalse(doc.isTransforming)
        XCTAssertNil(doc.selection, "applying deselects")
        doc.reselect()
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 3, minY: 2, maxX: 5, maxY: 4), "Reselect brings back the moved selection")
        doc.undo()
        doc.undo()
        XCTAssertEqual(pixel(doc, 1, 1), .black)
        XCTAssertEqual(pixel(doc, 4, 3), .clear)
        XCTAssertEqual(doc.selection?.bounds, PixelRect(minX: 0, minY: 0, maxX: 2, maxY: 2), "undo restores the original selection")
    }

    func testCancelAndDuplicate() {
        let doc = makeDocument()
        doc.beginStroke(at: PixelPoint(x: 1, y: 1))
        doc.endStroke()
        select(doc, .selectRectangle, from: PixelPoint(x: 0, y: 0), to: PixelPoint(x: 2, y: 2))
        doc.beginTransform()
        doc.continueTransformDrag(to: .zero)
        doc.nudgeTransform(dx: 3, dy: 0)
        doc.cancelTransform()
        XCTAssertEqual(pixel(doc, 1, 1), .black)
        XCTAssertEqual(pixel(doc, 4, 1), .clear)

        doc.beginTransform(copy: true)
        doc.nudgeTransform(dx: 3, dy: 0)
        doc.applyTransform()
        XCTAssertEqual(pixel(doc, 1, 1), .black)
        XCTAssertEqual(pixel(doc, 4, 1), .black)
    }

    func testFlipWithoutSelectionMirrorsTheCel() {
        let doc = makeDocument()
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.endStroke()
        doc.flip(horizontal: true)
        doc.applyTransform()
        XCTAssertEqual(pixel(doc, 7, 0), .black)
        XCTAssertEqual(pixel(doc, 0, 0), .clear)
    }

    func testCopyPasteDeleteFill() {
        let doc = makeDocument()
        doc.beginStroke(at: PixelPoint(x: 1, y: 1))
        doc.endStroke()
        select(doc, .selectRectangle, from: PixelPoint(x: 1, y: 1), to: PixelPoint(x: 2, y: 2))
        doc.copy()
        doc.deleteSelection()
        XCTAssertEqual(pixel(doc, 1, 1), .clear)
        doc.paste()
        XCTAssertTrue(doc.isTransforming)
        doc.applyTransform()
        XCTAssertEqual(pixel(doc, 1, 1), .black, "pastes at the copied position")
        doc.selectAll()
        doc.primary = .white
        doc.fillSelection()
        XCTAssertEqual(pixel(doc, 7, 7), .white)
    }

    func testCropToSelectionAndTrim() {
        let doc = makeDocument()
        doc.beginStroke(at: PixelPoint(x: 5, y: 6))
        doc.endStroke()
        doc.trimCanvas()
        XCTAssertEqual([doc.sprite.width, doc.sprite.height], [1, 1])
        doc.undo()
        XCTAssertEqual([doc.sprite.width, doc.sprite.height], [8, 8])
        select(doc, .selectRectangle, from: PixelPoint(x: 2, y: 2), to: PixelPoint(x: 5, y: 3))
        doc.cropToSelection()
        XCTAssertEqual([doc.sprite.width, doc.sprite.height], [4, 2])
        XCTAssertNil(doc.selection)
    }

    func testChangingFrameDropsFloatingPixels() {
        let doc = makeDocument()
        doc.beginStroke(at: PixelPoint(x: 0, y: 0))
        doc.endStroke()
        doc.addFrame()
        doc.goToFrame(0)
        doc.beginTransform()
        doc.nudgeTransform(dx: 2, dy: 0)
        doc.goToFrame(1)
        XCTAssertFalse(doc.isTransforming)
        XCTAssertEqual(doc.sprite.composite(frameIndex: 0)[2, 0], .black)
    }
}
