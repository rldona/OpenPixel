import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import OpenPixel

@MainActor
final class PreferencesAndExtensionsTests: XCTestCase {
    override func tearDown() {
        EditorSettings.reset()
        super.tearDown()
    }

    // MARK: Preferences

    func testAlphaFormat() {
        XCTAssertEqual(AlphaFormat.percent.text(0.5), "50 %")
        XCTAssertEqual(AlphaFormat.byte.text(0.5), "128")
        XCTAssertEqual(AlphaFormat.byte.text(2), "255", "clamped")
    }

    func testUndoLimit() {
        UserDefaults.standard.set(25, forKey: EditorSettings.undoLimitKey)
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 6, height: 6, background: nil, palette: []))
        doc.select(.pencil)
        for i in 0..<30 {
            doc.beginStroke(at: PixelPoint(x: i % 6, y: i / 6))
            doc.endStroke()
        }
        var undos = 0
        while doc.canUndo { doc.undo(); undos += 1 }
        XCTAssertEqual(undos, 25)
    }

    func testRewindOnStop() {
        var sprite = Sprite.blank(width: 2, height: 2, background: nil, palette: [])
        for i in 1..<4 { sprite.insertFrame(Frame(duration: 100), at: i) }
        let doc = SpriteDocument(name: "Doc", sprite: sprite)
        // Playback moves the active frame; here it's moved by hand while playing.
        doc.goToFrame(1)
        doc.togglePlayback()
        doc.activeFrameIndex = 3
        doc.togglePlayback()
        XCTAssertEqual(doc.activeFrameIndex, 3, "off: stays where it stopped")

        UserDefaults.standard.set(true, forKey: EditorSettings.rewindOnStopKey)
        doc.goToFrame(1)
        doc.togglePlayback()
        doc.activeFrameIndex = 3
        doc.togglePlayback()
        XCTAssertEqual(doc.activeFrameIndex, 1, "on: back to where it started")
    }

    func testPencilActions() {
        let doc = SpriteDocument(name: "Doc", sprite: .blank(width: 2, height: 2, background: nil, palette: []))
        doc.select(.pencil)
        doc.perform(.eyedropper)
        XCTAssertEqual(doc.tool, .eyedropper)
        doc.perform(.eyedropper)
        XCTAssertEqual(doc.tool, .pencil, "a second time goes back")
        doc.perform(.eraser)
        XCTAssertEqual(doc.tool, .eraser)
        let primary = doc.primary, secondary = doc.secondary
        doc.perform(.swapColors)
        XCTAssertEqual(doc.primary, secondary)
        XCTAssertEqual(doc.secondary, primary)
        doc.perform(.nothing)
        XCTAssertEqual(doc.tool, .eraser)
    }

    // MARK: Extensions

    func testZipReadsStoredAndDeflatedFiles() throws {
        let text = Data(String(repeating: "pixel ", count: 50).utf8)
        let zip = try Self.zip([("a.txt", Data("hi".utf8), false), ("folder/b.txt", text, true)])
        let archive = try ZipArchive(zip)
        XCTAssertEqual(archive.paths, ["a.txt", "folder/b.txt"])
        XCTAssertEqual(try archive.data(at: "./a.txt"), Data("hi".utf8))
        XCTAssertEqual(try archive.data(at: "folder/b.txt"), text)
        XCTAssertNil(try archive.data(at: "missing"))
        XCTAssertThrowsError(try ZipArchive(Data("not a zip".utf8)))
    }

    func testExtensionPalettesAndMatrices() throws {
        let package = """
        {"name": "retro", "displayName": "Retro pack", "version": "1.2", "author": {"name": "Someone"},
         "contributes": {
           "palettes": [{"id": "Four greens", "path": "./palettes/greens.gpl"}],
           "ditheringMatrices": [{"id": "lines", "name": "Lines", "path": "./lines.png"}],
           "themes": [{"id": "dark", "path": "./theme"}]
         }}
        """
        let gpl = "GIMP Palette\n#\n15 56 15\n48 98 48\n139 172 15\n155 188 15\n"
        // A 2×2 matrix with three levels: 0, 128 (twice) and 255.
        var matrix = PixelImage(width: 2, height: 2)
        matrix[0, 0] = PixelColor(r: 0, g: 0, b: 0)
        matrix[1, 0] = PixelColor(r: 128, g: 128, b: 128)
        matrix[0, 1] = PixelColor(r: 255, g: 255, b: 255)
        matrix[1, 1] = PixelColor(r: 128, g: 128, b: 128)
        let zip = try Self.zip([
            ("retro/package.json", Data(package.utf8), true),
            ("retro/palettes/greens.gpl", Data(gpl.utf8), true),
            ("retro/lines.png", try Exporter.pngData(matrix), false),
        ])
        let read = try AsepriteExtension.read(zip)
        XCTAssertEqual(read.displayName, "Retro pack")
        XCTAssertEqual(read.version, "1.2")
        XCTAssertEqual(read.author, "Someone")
        XCTAssertEqual(read.palettes.first?.id, "Four greens")
        XCTAssertEqual(read.palettes.first?.colors.first, PixelColor(r: 15, g: 56, b: 15))
        XCTAssertEqual(read.palettes.first?.colors.count, 4)
        XCTAssertEqual(read.leftOut, ["themes"])
        let lines = try XCTUnwrap(read.ditheringMatrices.first)
        XCTAssertEqual(lines.name, "Lines")
        XCTAssertEqual(lines.thresholds, [[1.0 / 6, 0.5], [5.0 / 6, 0.5]])

        let gradient = Gradient(from: .black, to: .white, a: PixelPoint(x: 0, y: 0), b: PixelPoint(x: 10, y: 0), shape: .linear, dither: lines)
        XCTAssertEqual(gradient.color(at: PixelPoint(x: 3, y: 0)), .black, "t 0.3 is past the lowest level only")
        XCTAssertEqual(gradient.color(at: PixelPoint(x: 2, y: 2)), .white)
    }

    func testExtensionWithNothingUsable() throws {
        let zip = try Self.zip([("package.json", Data(#"{"name": "t", "contributes": {"themes": [{"id": "x"}]}}"#.utf8), false)])
        XCTAssertThrowsError(try AsepriteExtension.read(zip)) { error in
            guard case AsepriteExtension.Failure.nothingToUse(let kinds) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(kinds, ["themes"])
        }
        XCTAssertThrowsError(try AsepriteExtension.read(Self.zip([("readme.txt", Data(), false)])))
    }

    /// A minimal ZIP writer for the tests: each file stored or deflated.
    static func zip(_ files: [(String, Data, Bool)]) throws -> Data {
        var out = [UInt8](), central = [UInt8]()
        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        func u32(_ v: Int) -> [UInt8] { u16(v & 0xFFFF) + u16(v >> 16 & 0xFFFF) }
        for (name, data, deflate) in files {
            let raw = [UInt8](data)
            // Zlib.deflate adds a zlib header and checksum around raw deflate.
            let body = deflate ? Array(try Zlib.deflate(raw).dropFirst(2).dropLast(4)) : raw
            let nameBytes = [UInt8](name.utf8)
            let offset = out.count
            let common = u16(20) + u16(0) + u16(deflate ? 8 : 0) + u16(0) + u16(0) + u32(0) + u32(body.count) + u32(raw.count) + u16(nameBytes.count) + u16(0)
            out += u32(0x0403_4B50) + common + nameBytes + body
            central += u32(0x0201_4B50) + u16(20) + common + u16(0) + u16(0) + u16(0) + u32(0) + u32(offset) + nameBytes
        }
        let start = out.count
        out += central
        out += u32(0x0605_4B50) + u16(0) + u16(0) + u16(files.count) + u16(files.count) + u32(central.count) + u32(start) + u16(0)
        return Data(out)
    }
}
