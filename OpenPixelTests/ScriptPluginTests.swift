import XCTest
@testable import OpenPixel

/// Extensions with scripts: dofile, plugin commands and preferences, events, selections.
@MainActor
final class ScriptPluginTests: XCTestCase {
    private func settle() async {
        for _ in 0..<10 { await Task.yield() }
    }

    private func stroke(_ doc: SpriteDocument, _ points: [PixelPoint]) {
        doc.select(.pencil)
        doc.beginStroke(at: points[0])
        for p in points.dropFirst() { doc.continueStroke(to: p) }
        doc.endStroke()
    }

    /// A plugin that turns every new stroke pixel blue once its command runs (like Magic Pencil's modes).
    private func makePackage() throws -> Data {
        let package = #"{"name": "blue-pencil", "displayName": "Blue pencil", "contributes": {"scripts": [{"path": "./main.lua"}]}}"#
        let main = """
        local Paint = dofile("./lib/paint.lua")
        function init(plugin)
          plugin.preferences.runs = (plugin.preferences.runs or 0)
          plugin:newCommand{ id = "BluePencil", title = "Blue pencil", onclick = function()
            plugin.preferences.runs = plugin.preferences.runs + 1
            local sprite = app.activeSprite
            local before = app.activeCel and app.activeCel.image:clone() or Image(sprite.width, sprite.height)
            local listener
            listener = sprite.events:on("change", function(ev)
              if ev.fromUndo then return end
              Paint(app.activeCel.image, before)
              before = app.activeCel.image:clone()
              sprite.events:off(listener)
            end)
          end }
        end
        """
        let paint = """
        local blue = dofile("../colors.lua").blue
        return function(image, before)
          for y = 0, image.height - 1 do
            for x = 0, image.width - 1 do
              if image:getPixel(x, y) ~= before:getPixel(x, y) then image:drawPixel(x, y, blue) end
            end
          end
        end
        """
        let colors = "return { blue = Color(0, 0, 255) }"
        return try PreferencesAndExtensionsTests.zip([
            ("blue/package.json", Data(package.utf8), false), ("blue/main.lua", Data(main.utf8), true),
            ("blue/lib/paint.lua", Data(paint.utf8), true), ("blue/colors.lua", Data(colors.utf8), false),
        ])
    }

    func testPluginCommandAnswersTheNextStroke() async throws {
        let package = try ExtensionStore.shared.install(makePackage())
        defer { ExtensionStore.shared.remove(package.id) }
        XCTAssertEqual(package.commands, [AsepriteExtension.Command(id: "BluePencil", title: "Blue pencil", script: "main.lua")])

        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 8, background: nil, palette: []))
        doc.primary = PixelColor(r: 255, g: 0, b: 0)
        doc.runCommand(try XCTUnwrap(package.commands?.first), of: package)
        XCTAssertNil(doc.scriptMessage?.text)
        stroke(doc, [PixelPoint(x: 1, y: 1), PixelPoint(x: 3, y: 1)])
        await settle()
        XCTAssertNil(doc.scriptMessage?.text)
        let cel = try XCTUnwrap(doc.sprite.cels[doc.activeCelKey])
        XCTAssertEqual((1...3).map { cel[$0, 1] }, Array(repeating: PixelColor(r: 0, g: 0, b: 255), count: 3), "the stroke, recolored")
        doc.undo()
        XCTAssertNil(doc.sprite.cels[doc.activeCelKey], "the stroke and the script's change are one undo step")

        // It stopped listening, so the next stroke stays red.
        stroke(doc, [PixelPoint(x: 1, y: 5)])
        await settle()
        XCTAssertEqual(doc.sprite.cels[doc.activeCelKey]?[1, 5], PixelColor(r: 255, g: 0, b: 0))
        XCTAssertEqual(UserDefaults.standard.dictionary(forKey: "extension.blue-pencil.preferences")?["runs"] as? Double, 1, "plugin.preferences are kept")
        UserDefaults.standard.removeObject(forKey: "extension.blue-pencil.preferences")
    }

    func testDofileStaysInItsFolder() throws {
        let zip = try PreferencesAndExtensionsTests.zip([
            ("package.json", Data(#"{"name": "escape", "contributes": {"scripts": [{"path": "./main.lua"}]}}"#.utf8), false),
            ("main.lua", Data(#"function init(plugin) dofile("../../outside.lua") end"#.utf8), false),
        ])
        let package = try ExtensionStore.shared.install(zip)
        defer { ExtensionStore.shared.remove(package.id) }
        XCTAssertEqual(package.commands ?? [], [])
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 4, height: 4, background: nil, palette: []))
        let engine = ScriptEngine(name: "escape", document: doc, folder: ExtensionStore.shared.folder(of: package))
        engine.startPlugin(entry: "main.lua", command: nil)
        XCTAssertEqual(doc.scriptMessage?.text, "main.lua:1: " + L10n.string("Scripts can only read files in their own folder"))
    }

    func testSelectionsAndCelPositions() throws {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 8, height: 8, background: nil, palette: []))
        doc.runScript(named: "Test", source: """
        local s = app.activeSprite
        local cel = s:newCel(app.activeLayer, 1)
        local small = Image(2, 2)
        small:clear(Color(255, 0, 0))
        cel.image = small
        cel.position = Point(5, 6)
        assert(cel.bounds == Rectangle(5, 6, 2, 2))
        local sel = Selection(Rectangle(1, 1, 3, 3))
        sel:subtract(Rectangle(2, 2, 1, 1))
        assert(sel:contains(1, 1) and not sel:contains(2, 2) and sel.bounds == Rectangle(1, 1, 3, 3))
        s.selection:add(sel)
        assert(not s.selection.isEmpty)
        assert(Rectangle(0, 0, 4, 4):union(Rectangle(2, 2, 4, 4)) == Rectangle(0, 0, 6, 6))
        assert(app.tool.id == "pencil" and app.preferences.tool("pencil").brush.size == 1)
        """)
        XCTAssertNil(doc.scriptMessage?.text)
        let cel = try XCTUnwrap(doc.sprite.cels[doc.activeCelKey])
        XCTAssertEqual(cel[5, 6], PixelColor(r: 255, g: 0, b: 0), "flattened at its position")
        XCTAssertEqual(cel[0, 0], .clear)
        XCTAssertTrue(doc.hasSelection)
    }
}
