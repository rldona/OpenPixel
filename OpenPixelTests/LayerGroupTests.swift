import XCTest
@testable import OpenPixel

@MainActor
final class LayerGroupTests: XCTestCase {
    /// Three layers, bottom to top A, B, C, each with a dot at a different x.
    private func makeDocument() -> SpriteDocument {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 4, height: 1, background: nil, palette: []))
        doc.primary = .black
        doc.renameLayer(doc.activeLayerID, to: "A")
        dot(doc, 0)
        doc.addLayer(); doc.renameLayer(doc.activeLayerID, to: "B"); dot(doc, 1)
        doc.addLayer(); doc.renameLayer(doc.activeLayerID, to: "C"); dot(doc, 2)
        return doc
    }

    private func dot(_ doc: SpriteDocument, _ x: Int) {
        doc.beginStroke(at: PixelPoint(x: x, y: 0))
        doc.endStroke()
    }

    private func id(_ doc: SpriteDocument, _ name: String) -> UUID { doc.sprite.layers.first { $0.name == name }!.id }
    private func names(_ doc: SpriteDocument) -> [String] { doc.sprite.layers.map(\.name) }

    func testGroupSitsAboveItsChildren() {
        let doc = makeDocument()
        doc.groupLayers([id(doc, "A"), id(doc, "B")])
        let group = doc.sprite.layers.first(where: \.isGroup)!
        XCTAssertEqual(names(doc), ["A", "B", group.name, "C"])
        XCTAssertEqual(doc.activeLayerID, group.id)
        XCTAssertEqual(doc.sprite.layers[0].parent, group.id)
        XCTAssertEqual(doc.sprite.depth(of: doc.sprite.layers[1]), 1)
        doc.undo()
        XCTAssertFalse(doc.sprite.hasGroups, "one undo step")
    }

    func testNewGroupStartsEmptyAndTakesDroppedLayers() {
        let doc = makeDocument()
        doc.activeLayerID = id(doc, "C")
        doc.newGroup()
        let group = doc.activeLayerID
        XCTAssertEqual(names(doc).last, doc.sprite.layers.last?.name)
        XCTAssertTrue(doc.sprite.layers.last!.isGroup, "an empty group above the active layer")
        doc.moveLayer(id(doc, "A"), .into, group)
        doc.moveLayer(id(doc, "B"), .above, id(doc, "A"))
        XCTAssertEqual(doc.sprite.layers.first { $0.name == "A" }?.parent, group)
        XCTAssertEqual(doc.sprite.layers.first { $0.name == "B" }?.parent, group, "above a child is still inside")
        XCTAssertEqual(Array(names(doc).prefix(3)), ["C", "A", "B"])
    }

    func testDroppingAboveOrBelowAGroupStaysOutside() {
        let doc = makeDocument()
        doc.groupLayers([id(doc, "A"), id(doc, "B")])
        let group = doc.sprite.layers.first(where: \.isGroup)!.id
        doc.moveLayer(id(doc, "C"), .below, id(doc, "A"))
        XCTAssertEqual(doc.sprite.layers.first { $0.name == "C" }?.parent, group, "below a child goes in the group")
        XCTAssertEqual(names(doc).first, "C")
        doc.toggleExpanded(group)
        doc.moveLayer(id(doc, "C"), .above, group)
        XCTAssertNil(doc.sprite.layers.first { $0.name == "C" }?.parent)
        XCTAssertEqual(names(doc).last, "C")
        doc.moveLayer(id(doc, "C"), .below, group)
        XCTAssertNil(doc.sprite.layers.first { $0.name == "C" }?.parent, "below a closed group: out of it, under its layers")
        XCTAssertEqual(names(doc).first, "C")
    }

    func testCheckedLayersGoIntoTheNewGroup() {
        let doc = makeDocument()
        doc.toggleLayerCheck(id(doc, "A"))
        doc.toggleLayerCheck(id(doc, "B"))
        doc.newGroup()
        let group = doc.sprite.layers.first(where: \.isGroup)!.id
        XCTAssertEqual(doc.sprite.layers.filter { $0.parent == group }.map(\.name), ["A", "B"])
        XCTAssertNil(doc.timelineRange)
    }

    func testGroupVisibilityOpacityAndLockApplyToChildren() {
        let doc = makeDocument()
        doc.groupLayers([id(doc, "A"), id(doc, "B")])
        let group = doc.sprite.layers.first(where: \.isGroup)!.id
        XCTAssertEqual(doc.sprite.composite(frameIndex: 0)[1, 0], .black)
        doc.setOpacity(0.5, layer: group)
        XCTAssertEqual(Int(doc.sprite.composite(frameIndex: 0)[1, 0].a), 128, accuracy: 1)
        XCTAssertEqual(doc.sprite.composite(frameIndex: 0)[2, 0].a, 255, "outside the group")
        doc.toggleVisibility(group)
        XCTAssertEqual(doc.sprite.composite(frameIndex: 0)[1, 0], .clear)
        doc.toggleVisibility(group)
        doc.toggleLock(group)
        doc.activeLayerID = id(doc, "B")
        doc.beginStroke(at: PixelPoint(x: 3, y: 0))
        doc.endStroke()
        XCTAssertNotNil(doc.notice, "locked by its group")
        doc.notice = nil
        doc.activeLayerID = group
        doc.beginStroke(at: PixelPoint(x: 3, y: 0))
        XCTAssertNotNil(doc.notice, "can't draw on a group")
    }

    func testMovingAGroupMovesItsChildren() {
        let doc = makeDocument()
        doc.groupLayers([id(doc, "A"), id(doc, "B")])
        let group = doc.sprite.layers.first(where: \.isGroup)!
        doc.moveLayer(group.id, by: 1)
        XCTAssertEqual(names(doc), ["C", "A", "B", group.name])
        doc.moveLayer(group.id, by: -1)
        XCTAssertEqual(names(doc), ["A", "B", group.name, "C"])
        // A child moves only among its siblings.
        doc.moveLayer(id(doc, "B"), by: 1)
        XCTAssertEqual(names(doc), ["A", "B", group.name, "C"], "B is already on top of the group")
        doc.moveLayer(id(doc, "B"), by: -1)
        XCTAssertEqual(names(doc), ["B", "A", group.name, "C"])
        // What the timeline's up and down buttons check.
        XCTAssertTrue(doc.canMoveLayer(id(doc, "B"), by: 1))
        XCTAssertFalse(doc.canMoveLayer(id(doc, "B"), by: -1), "already the group's bottom layer")
        XCTAssertFalse(doc.canMoveLayer(id(doc, "C"), by: 1), "already on top")
        XCTAssertTrue(doc.canMoveLayer(group.id, by: 1))
    }

    func testTheMoveToolMovesEveryLayerInAGroup() {
        let doc = makeDocument()
        doc.groupLayers([id(doc, "A"), id(doc, "B")])
        doc.select(.move)
        doc.beginTransformDrag(.move, at: CGPoint(x: 0.5, y: 0.5))
        doc.continueTransformDrag(to: CGPoint(x: 1.5, y: 0.5))
        doc.endTransformDrag()
        doc.applyTransform()
        let s = doc.sprite, frame = s.frames[0].id
        XCTAssertEqual(s.cel(layer: id(doc, "A"), frame: frame)?[1, 0], .black, "A's dot moved right")
        XCTAssertEqual(s.cel(layer: id(doc, "A"), frame: frame)?[0, 0], .clear)
        XCTAssertEqual(s.cel(layer: id(doc, "B"), frame: frame)?[2, 0], .black, "B's dot moved right")
        XCTAssertEqual(s.cel(layer: id(doc, "B"), frame: frame)?[1, 0], .clear)
        XCTAssertEqual(s.cel(layer: id(doc, "C"), frame: frame)?[2, 0], .black, "C, outside the group, stays")
        doc.undo()
        XCTAssertEqual(doc.sprite.cel(layer: id(doc, "A"), frame: frame)?[0, 0], .black, "one undo step")
    }

    func testCopyCutAndPasteAGroupWithItsLayers() {
        let doc = makeDocument()
        doc.groupLayers([id(doc, "A"), id(doc, "B")])
        let group = doc.sprite.layers.first(where: \.isGroup)!
        doc.cutLayer(group.id)
        XCTAssertEqual(names(doc), ["C"], "the group and its layers are gone")
        // Pasted into another sprite, the group keeps its layers and pixels.
        let other = SpriteDocument(name: "Other", sprite: .blank(width: 4, height: 1, background: nil, palette: []))
        other.pasteLayers()
        let pasted = other.sprite
        XCTAssertEqual(pasted.layers.map(\.name), [pasted.layers[0].name, "A", "B", group.name])
        let pastedGroup = pasted.layers.first(where: \.isGroup)!
        XCTAssertNotEqual(pastedGroup.id, group.id)
        XCTAssertEqual(pasted.descendants(of: pastedGroup.id).map(\.name), ["A", "B"])
        let a = pasted.layers.first { $0.name == "A" }!
        XCTAssertEqual(pasted.cel(layer: a.id, frame: pasted.frames[0].id)?[0, 0], .black)
        // And it can be pasted again in the first one.
        doc.pasteLayers()
        XCTAssertEqual(doc.sprite.layers.filter(\.isGroup).count, 1)
        XCTAssertEqual(names(doc).filter { $0 == "A" }.count, 1)
    }

    func testIntoOutOfUngroupAndDelete() {
        let doc = makeDocument()
        doc.groupLayers([id(doc, "A")])
        let group = doc.sprite.layers.first(where: \.isGroup)!
        doc.moveIntoGroup(id(doc, "C"), group: group.id)
        XCTAssertEqual(names(doc), ["A", "C", group.name, "B"])
        doc.removeFromGroup(id(doc, "C"))
        XCTAssertEqual(names(doc), ["A", group.name, "C", "B"])
        XCTAssertNil(doc.sprite.layers.first { $0.name == "C" }?.parent)
        doc.ungroup(group.id)
        XCTAssertFalse(doc.sprite.hasGroups)
        XCTAssertEqual(names(doc), ["A", "C", "B"])

        doc.groupLayers([id(doc, "A"), id(doc, "C")])
        let second = doc.sprite.layers.first(where: \.isGroup)!
        doc.deleteLayer(second.id)
        XCTAssertEqual(names(doc), ["B"], "deleting a group deletes its layers")
        XCTAssertEqual(doc.activeLayerID, id(doc, "B"))
    }

    func testDuplicateGroupAndNewLayerInsideAndSave() throws {
        let doc = makeDocument()
        doc.groupLayers([id(doc, "A"), id(doc, "B")])
        let group = doc.sprite.layers.first(where: \.isGroup)!
        doc.duplicateLayer(group.id)
        let groups = doc.sprite.layers.filter(\.isGroup)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(doc.sprite.layers.filter { $0.parent == groups[1].id }.count, 2, "the copy has its own children")
        doc.activeLayerID = group.id
        doc.addLayer()
        XCTAssertEqual(doc.activeLayer?.parent, group.id, "a new layer on a group goes inside it")
        let data = try JSONEncoder().encode(doc.sprite)
        let decoded = try JSONDecoder().decode(Sprite.self, from: data)
        XCTAssertEqual(decoded.layers.map(\.parent), doc.sprite.layers.map(\.parent))
        XCTAssertEqual(decoded.layers.map(\.isGroup), doc.sprite.layers.map(\.isGroup))
    }

    func testCollapsingIsNotAnUndoStep() {
        let doc = makeDocument()
        doc.groupLayers([id(doc, "A")])
        let group = doc.sprite.layers.first(where: \.isGroup)!.id
        let steps = doc.canUndo
        doc.toggleExpanded(group)
        XCTAssertFalse(doc.sprite.layers.first { $0.id == group }!.isExpanded)
        doc.undo()
        XCTAssertFalse(doc.sprite.hasGroups, "undo skipped the collapse and undid the grouping")
        XCTAssertTrue(steps)
    }
}
