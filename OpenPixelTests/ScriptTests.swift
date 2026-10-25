import XCTest
@testable import OpenPixel

@MainActor
final class ScriptTests: XCTestCase {
    private func makeDocument() -> SpriteDocument {
        SpriteDocument(name: "Doc", sprite: .blank(width: 16, height: 16, background: nil, palette: []))
    }

    private func run(_ source: String, on doc: SpriteDocument) {
        doc.runScript(named: "Test", source: source)
    }

    func testPixelsLayersAndOneUndoStep() throws {
        let doc = makeDocument()
        let layersBefore = doc.sprite.layers.count
        run("""
        local s = app.activeSprite
        local layer = s:newLayer()
        layer.name = "Box"
        s:newCel(layer, 1)
        local c = Color{ h=120, s=1, v=1, a=255 }
        app.activeImage:putPixel(2, 3, c)
        app.activeImage:putPixel(4, 3, app.pixelColor.rgba(255, 0, 0, 255))
        assert(app.activeImage:getPixel(2, 3) == app.pixelColor.rgba(0, 255, 0, 255))
        assert(app.pixelColor.rgbaR(app.activeImage:getPixel(4, 3)) == 255)
        assert(c.hsvHue == 120 and c.green == 255)
        assert(s.width == 16 and #s.layers == \(layersBefore + 1))
        """, on: doc)
        XCTAssertNil(doc.scriptMessage?.text)
        XCTAssertEqual(doc.sprite.layers.count, layersBefore + 1)
        let layer = try XCTUnwrap(doc.activeLayer)
        XCTAssertEqual(layer.name, "Box", "the new layer is the active one")
        let image = try XCTUnwrap(doc.sprite.cels[CelKey(layer: layer.id, frame: doc.sprite.frames[0].id)])
        XCTAssertEqual(image[2, 3], PixelColor(r: 0, g: 255, b: 0))
        XCTAssertEqual(image[4, 3], PixelColor(r: 255, g: 0, b: 0))
        doc.undo()
        XCTAssertEqual(doc.sprite.layers.count, layersBefore, "the whole script is one undo step")
    }

    func testErrorsNameWhatsMissing() {
        let doc = makeDocument()
        run("local x = app.activeSprite.tags", on: doc)
        XCTAssertTrue(doc.scriptMessage?.text.contains("Sprite.tags") == true, doc.scriptMessage?.text ?? "")
        XCTAssertTrue(doc.scriptMessage?.text.contains("Test.lua:1") == true, "with the line")

        run("app.command.ColorQuantization()", on: doc)
        XCTAssertTrue(doc.scriptMessage?.text.contains("app.command.ColorQuantization") == true)
    }

    func testSandbox() {
        let doc = makeDocument()
        run("assert(io == nil and os == nil and package == nil and debug == nil and loadfile == nil and require == nil)", on: doc)
        XCTAssertNil(doc.scriptMessage)
        run("dofile('/etc/hosts')", on: doc)
        XCTAssertNotNil(doc.scriptMessage, "a loose script has no folder to read from")
        doc.scriptMessage = nil
        run("load(string.dump(function() end))()", on: doc)
        XCTAssertNotNil(doc.scriptMessage, "no bytecode")
    }

    func testRunawayScriptIsStopped() {
        let doc = makeDocument()
        ScriptEngine.timeLimit = 0.2
        defer { ScriptEngine.timeLimit = 10 }
        run("while true do end", on: doc)
        XCTAssertNotNil(doc.scriptMessage)
    }

    func testDialogCallbacks() throws {
        let doc = makeDocument()
        run("""
        app.activeSprite:newCel(app.activeLayer, 1)
        local dlg = Dialog("Fill")
        dlg:slider{ id="size", label="Size:", min=1, max=8, value=3 }
           :color{ id="color", label="Color:", color=Color(0, 0, 255) }
           :radio{ id="a", label="Mode:", text="A", selected=false }
           :radio{ id="b", text="B", selected=true }
           :button{ id="ok", text="Fill", onclick=function()
              local d = dlg.data
              assert(d.b and not d.a)
              local img = app.activeImage
              for x = 0, d.size - 1 do img:putPixel(x, 0, d.color) end
           end }
           :show{ wait=false }
        """, on: doc)
        XCTAssertNil(doc.scriptMessage?.text)
        let dialog = try XCTUnwrap(doc.scriptDialogs.first)
        XCTAssertEqual(dialog.rows.count, 3, "slider, color, then both radios and the unlabelled button on one row, as in Aseprite")
        let button = try XCTUnwrap(dialog.widgets.first { $0.kind == .button })
        dialog.engine?.clicked(button, in: dialog)
        XCTAssertNil(doc.scriptMessage?.text)
        let cel = try XCTUnwrap(doc.sprite.cels[doc.activeCelKey])
        XCTAssertEqual((0..<4).map { cel[$0, 0] }, [PixelColor(r: 0, g: 0, b: 255), PixelColor(r: 0, g: 0, b: 255), PixelColor(r: 0, g: 0, b: 255), .clear])
        dialog.engine?.close(dialog)
        XCTAssertTrue(doc.scriptDialogs.isEmpty)
    }

    func testShowWaitsForTheDialog() async throws {
        let doc = makeDocument()
        run("""
        app.activeSprite:newCel(app.activeLayer, 1)
        local dlg = Dialog("Ask"):number{ id="n", text="5" }:button{ id="ok", text="OK" }
        dlg:show()
        if dlg.data.ok then app.activeImage:putPixel(dlg.data.n, 0, Color(255, 0, 0)) end
        """, on: doc)
        let dialog = try XCTUnwrap(doc.scriptDialogs.first)
        XCTAssertEqual(doc.sprite.cels[doc.activeCelKey]?[5, 0], .clear, "waiting")
        dialog.engine?.clicked(try XCTUnwrap(dialog.widgets.last), in: dialog)
        for _ in 0..<20 where doc.sprite.cels[doc.activeCelKey]?[5, 0] == .clear { await Task.yield() }
        XCTAssertNil(doc.scriptMessage?.text)
        XCTAssertEqual(doc.sprite.cels[doc.activeCelKey]?[5, 0], PixelColor(r: 255, g: 0, b: 0), "ran on after the dialog closed")
    }
}
