import Compression
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Reads and writes Aseprite's own `.aseprite` / `.ase` files, so sprites go
/// back and forth with Aseprite without losing layers, frames, tags or slices.
/// https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md
enum AsepriteFile {
    enum Failure: LocalizedError {
        case notAseprite, damaged, tooLarge

        var errorDescription: String? {
            switch self {
            case .notAseprite: L10n.string("This isn't an Aseprite file.")
            case .damaged: L10n.string("The Aseprite file is damaged.")
            case .tooLarge: L10n.string("The image is too large (maximum %d × %d px).", DocumentStore.maxImportSize, DocumentStore.maxImportSize)
            }
        }
    }

    // MARK: Reading

    /// What a cel chunk holds, before the palette (which may come later) turns it into colors.
    private enum CelContent {
        case image(width: Int, height: Int, bytes: [UInt8])
        case link(frame: Int)
        case tilemap(columns: Int, rows: Int, tiles: [UInt32], idMask: UInt32, xFlip: UInt32, yFlip: UInt32, dFlip: UInt32)
    }

    private struct FileCel {
        var layer: Int
        var frame: Int
        var x: Int
        var y: Int
        var opacity: Int
        var content: CelContent
        /// A reference layer's position and size in sprite pixels (the Cel Extra chunk).
        var preciseBounds: CGRect?
    }

    private struct FileLayer {
        var layer: Layer
        var level: Int
        var tilesetIndex: Int?
    }

    /// What the next User Data chunk belongs to.
    private enum UserDataTarget {
        case none, tag(Int), slice(Int)
    }

    static func read(_ data: Data) throws -> Sprite {
        var r = ByteReader(data)
        _ = try r.u32()
        guard try r.u16() == 0xA5E0 else { throw Failure.notAseprite }
        let frameCount = try r.u16()
        let width = try r.u16(), height = try r.u16()
        let depth = try r.u16()
        let flags = try r.u32()
        let speed = try r.u16()
        try r.skip(8)
        let transparentIndex = Int(try r.u8())
        try r.skip(3)
        _ = try r.u16()
        let pixelWidth = Int(try r.u8()), pixelHeight = Int(try r.u8())
        let gridX = Int(try r.i16()), gridY = Int(try r.i16())
        let gridWidth = try r.u16(), gridHeight = try r.u16()
        try r.skip(84)

        guard [8, 16, 32].contains(depth), width > 0, height > 0, frameCount > 0 else { throw Failure.damaged }
        guard width <= DocumentStore.maxImportSize, height <= DocumentStore.maxImportSize else { throw Failure.tooLarge }
        let bytesPerPixel = depth / 8

        var frames: [Frame] = []
        var fileLayers: [FileLayer] = []
        var cels: [FileCel] = []
        var palette: [PixelColor] = []
        var oldPalette: [PixelColor] = []
        var tags: [FrameTag] = []
        var slices: [Slice] = []
        var tilesets: [Int: Tileset] = [:]
        // Raw tileset images, kept until the palette (which may come later) is known.
        var tilesetBytes: [Int: (width: Int, height: Int, count: Int, bytes: [UInt8])] = [:]
        var target = UserDataTarget.none

        for frameIndex in 0..<frameCount {
            let frameStart = r.position
            let frameBytes = try r.u32()
            guard try r.u16() == 0xF1FA else { throw Failure.damaged }
            let oldChunks = try r.u16()
            let duration = try r.u16()
            try r.skip(2)
            let newChunks = try r.u32()
            frames.append(Frame(duration: duration > 0 ? duration : max(1, speed)))
            let chunkCount = newChunks != 0 ? newChunks : oldChunks

            for _ in 0..<chunkCount {
                let chunkStart = r.position
                let size = try r.u32()
                let type = try r.u16()
                let end = chunkStart + size
                guard size >= 6, end <= r.count else { throw Failure.damaged }

                switch type {
                case 0x0004:
                    oldPalette = try readOldPalette(&r)
                case 0x2004:
                    let layerFlags = try r.u16(), layerType = try r.u16(), level = try r.u16()
                    try r.skip(4)
                    let blend = try r.u16(), opacity = try r.u8()
                    try r.skip(3)
                    var layer = Layer(name: try r.string())
                    let tilesetIndex = layerType == 2 ? try r.u32() : nil
                    layer.isVisible = layerFlags & 1 != 0
                    layer.isLocked = layerFlags & 2 == 0
                    layer.isBackground = layerFlags & 8 != 0
                    layer.isContinuous = layerFlags & 16 != 0
                    layer.isGroup = layerType == 1
                    layer.isExpanded = layerFlags & 32 == 0
                    layer.blendMode = blendMode(blend)
                    // The opacity is valid for groups only with header flag 2.
                    if flags & 1 != 0, layerType != 1 || flags & 2 != 0 { layer.opacity = Double(opacity) / 255 }
                    if layerFlags & 64 != 0 {
                        // Filled in from the layer's cel once cels are read.
                        layer.reference = ReferenceImage(data: Data(), frame: .zero)
                    }
                    fileLayers.append(FileLayer(layer: layer, level: level, tilesetIndex: tilesetIndex))
                    target = .none
                case 0x2005:
                    let layerIndex = try r.u16()
                    let x = Int(try r.i16()), y = Int(try r.i16())
                    let opacity = Int(try r.u8())
                    let celType = try r.u16()
                    try r.skip(7)
                    let content: CelContent
                    switch celType {
                    case 0:
                        let w = try r.u16(), h = try r.u16()
                        content = .image(width: w, height: h, bytes: try r.bytes(w * h * bytesPerPixel))
                    case 1:
                        content = .link(frame: try r.u16())
                    case 2:
                        let w = try r.u16(), h = try r.u16()
                        let bytes = try Zlib.inflate(try r.bytes(end - r.position), size: w * h * bytesPerPixel)
                        content = .image(width: w, height: h, bytes: bytes)
                    case 3:
                        let columns = try r.u16(), rows = try r.u16()
                        let bits = try r.u16()
                        let idMask = try r.u32(), xFlip = try r.u32(), yFlip = try r.u32(), dFlip = try r.u32()
                        try r.skip(10)
                        guard [8, 16, 32].contains(bits) else { throw Failure.damaged }
                        let raw = try Zlib.inflate(try r.bytes(end - r.position), size: columns * rows * bits / 8)
                        var tileReader = ByteReader(Data(raw))
                        var tiles: [UInt32] = []
                        tiles.reserveCapacity(columns * rows)
                        for _ in 0..<(columns * rows) {
                            switch bits {
                            case 8: tiles.append(UInt32(try tileReader.u8()))
                            case 16: tiles.append(UInt32(try tileReader.u16()))
                            default: tiles.append(UInt32(try tileReader.u32()))
                            }
                        }
                        content = .tilemap(columns: columns, rows: rows, tiles: tiles, idMask: UInt32(idMask), xFlip: UInt32(xFlip), yFlip: UInt32(yFlip), dFlip: UInt32(dFlip))
                    default:
                        r.position = end
                        continue
                    }
                    cels.append(FileCel(layer: layerIndex, frame: frameIndex, x: x, y: y, opacity: opacity, content: content))
                    target = .none
                case 0x2006:
                    let extraFlags = try r.u32()
                    if extraFlags & 1 != 0, !cels.isEmpty {
                        let x = try r.fixed(), y = try r.fixed(), w = try r.fixed(), h = try r.fixed()
                        cels[cels.count - 1].preciseBounds = CGRect(x: x, y: y, width: w, height: h)
                    }
                case 0x2018:
                    let count = try r.u16()
                    try r.skip(8)
                    let first = tags.count
                    for _ in 0..<count {
                        let from = try r.u16(), to = try r.u16()
                        let direction = try r.u8()
                        let repeatCount = try r.u16()
                        try r.skip(6)
                        let red = try r.u8(), green = try r.u8(), blue = try r.u8()
                        try r.skip(1)
                        tags.append(FrameTag(
                            name: try r.string(), from: from, to: to,
                            color: PixelColor(r: red, g: green, b: blue),
                            direction: [.forward, .reverse, .pingPong, .pingPongReverse][min(3, Int(direction))],
                            repeatCount: repeatCount
                        ))
                    }
                    target = count > 0 ? .tag(first) : .none
                case 0x2019:
                    let total = try r.u32(), from = try r.u32(), to = try r.u32()
                    try r.skip(8)
                    guard total <= 65536, from <= to, to < max(total, 1) else { throw Failure.damaged }
                    if palette.count < total { palette += Array(repeating: .black, count: total - palette.count) }
                    for i in from...to {
                        let entryFlags = try r.u16()
                        palette[i] = PixelColor(r: try r.u8(), g: try r.u8(), b: try r.u8(), a: try r.u8())
                        if entryFlags & 1 != 0 { _ = try r.string() }
                    }
                    target = .none
                case 0x2020:
                    let userFlags = try r.u32()
                    if userFlags & 1 != 0 { _ = try r.string() }
                    if userFlags & 2 != 0 {
                        let color = PixelColor(r: try r.u8(), g: try r.u8(), b: try r.u8(), a: try r.u8())
                        switch target {
                        case .tag(let i) where tags.indices.contains(i): tags[i].color = PixelColor(r: color.r, g: color.g, b: color.b)
                        case .slice(let i) where slices.indices.contains(i): slices[i].color = PixelColor(r: color.r, g: color.g, b: color.b)
                        default: break
                        }
                    }
                    if case .tag(let i) = target { target = i + 1 < tags.count ? .tag(i + 1) : .none } else { target = .none }
                case 0x2022:
                    let keyCount = try r.u32(), sliceFlags = try r.u32()
                    try r.skip(4)
                    let name = try r.string()
                    var keys: [(frame: Int, key: SliceKey)] = []
                    for _ in 0..<keyCount {
                        let frame = try r.u32()
                        let x = Int(try r.i32()), y = Int(try r.i32())
                        let w = try r.u32(), h = try r.u32()
                        var center: PixelRect?
                        var pivot: PixelPoint?
                        if sliceFlags & 1 != 0 {
                            let cx = Int(try r.i32()), cy = Int(try r.i32()), cw = try r.u32(), ch = try r.u32()
                            if cw > 0, ch > 0 { center = PixelRect(minX: cx, minY: cy, maxX: cx + cw - 1, maxY: cy + ch - 1) }
                        }
                        if sliceFlags & 2 != 0 { pivot = PixelPoint(x: Int(try r.i32()), y: Int(try r.i32())) }
                        // A zero size hides the slice from that frame on, which OpenPixel doesn't have.
                        guard w > 0, h > 0 else { continue }
                        keys.append((frame, SliceKey(frame: UUID(), bounds: PixelRect(minX: x, minY: y, maxX: x + w - 1, maxY: y + h - 1), center: center, pivot: pivot)))
                    }
                    // Frame IDs are known once every frame is read; the index travels in a placeholder.
                    slices.append(Slice(name: name, color: Slice.colors[slices.count % Slice.colors.count],
                                        keys: keys.map { var key = $0.key; key.frame = placeholder(for: $0.frame); return key }))
                    target = .slice(slices.count - 1)
                case 0x2023:
                    let id = try r.u32(), tilesetFlags = try r.u32()
                    let count = try r.u32()
                    let tileWidth = try r.u16(), tileHeight = try r.u16()
                    try r.skip(16)
                    _ = try r.string()
                    if tilesetFlags & 1 != 0 { try r.skip(8) }
                    if tilesetFlags & 2 != 0, tileWidth > 0, tileHeight > 0 {
                        let length = try r.u32()
                        let raw = try Zlib.inflate(try r.bytes(length), size: tileWidth * tileHeight * count * bytesPerPixel)
                        tilesetBytes[id] = (tileWidth, tileHeight, count, raw)
                    }
                    tilesets[id] = Tileset(tileWidth: max(1, tileWidth), tileHeight: max(1, tileHeight))
                    target = .none
                default:
                    break
                }
                r.position = end
            }
            r.position = frameStart + frameBytes
        }
        if palette.isEmpty { palette = oldPalette }
        func color(_ bytes: [UInt8], _ i: Int, opaqueIndex: Bool) -> PixelColor {
            switch bytesPerPixel {
            case 4: return PixelColor(r: bytes[i * 4], g: bytes[i * 4 + 1], b: bytes[i * 4 + 2], a: bytes[i * 4 + 3])
            case 2: return PixelColor(r: bytes[i * 2], g: bytes[i * 2], b: bytes[i * 2], a: bytes[i * 2 + 1])
            default:
                let index = Int(bytes[i])
                // In indexed sprites one entry is transparent, except on the background layer.
                if index == transparentIndex && !opaqueIndex { return .clear }
                return palette.indices.contains(index) ? palette[index] : .clear
            }
        }
        func image(_ w: Int, _ h: Int, _ bytes: [UInt8], opaqueIndex: Bool = false) -> PixelImage {
            var out = PixelImage(width: w, height: h)
            for i in 0..<(w * h) { out.pixels[i] = color(bytes, i, opaqueIndex: opaqueIndex) }
            return out
        }

        for (id, entry) in tilesetBytes {
            let sheet = image(entry.width, entry.height * entry.count, entry.bytes)
            var tileset = Tileset(tileWidth: entry.width, tileHeight: entry.height)
            tileset.tiles = (0..<entry.count).map { i in
                var tile = PixelImage(width: entry.width, height: entry.height)
                for y in 0..<entry.height { for x in 0..<entry.width { tile[x, y] = sheet[x, i * entry.height + y] } }
                return tile
            }
            if tileset.tiles.isEmpty { tileset.tiles = [PixelImage(width: entry.width, height: entry.height)] }
            tilesets[id] = tileset
        }

        // Layers: the file lists each group before its children, with child levels;
        // OpenPixel keeps each group right above its children.
        var stack: [Int] = []
        for i in fileLayers.indices {
            let level = fileLayers[i].level
            stack = Array(stack.prefix(level))
            if let parent = stack.last, fileLayers[parent].layer.isGroup { fileLayers[i].layer.parent = fileLayers[parent].layer.id }
            stack.append(i)
            if let index = fileLayers[i].tilesetIndex { fileLayers[i].layer.tileset = tilesets[index] ?? Tileset(tileWidth: 16, tileHeight: 16) }
        }

        var sprite = Sprite(width: width, height: height, layers: [], frames: frames, cels: [:],
                            palette: palette.isEmpty ? Palette.newSpriteDefault.colors : palette.map { var c = $0; c.a = 255; return c })
        if gridWidth > 0, gridHeight > 0 { sprite.grid = GridSettings(width: gridWidth, height: gridHeight, offsetX: gridX, offsetY: gridY) }
        if pixelWidth > 0, pixelHeight > 0 { sprite.pixelRatio = PixelRatio(width: pixelWidth, height: pixelHeight) }

        var linkGroups: [CelKey: UUID] = [:]
        var offGrid = false
        for cel in cels.sorted(by: { $0.frame < $1.frame }) {
            guard fileLayers.indices.contains(cel.layer), frames.indices.contains(cel.frame) else { continue }
            let layer = fileLayers[cel.layer].layer
            guard !layer.isGroup else { continue }
            let key = CelKey(layer: layer.id, frame: frames[cel.frame].id)
            switch cel.content {
            case .image(let w, let h, let bytes):
                let picture = image(w, h, bytes, opaqueIndex: layer.isBackground)
                if layer.isReference {
                    // A reference keeps its own resolution, placed by the Cel Extra bounds.
                    guard fileLayers[cel.layer].layer.reference?.data.isEmpty ?? false, let png = try? Exporter.pngData(picture) else { continue }
                    let frame = cel.preciseBounds ?? CGRect(x: cel.x, y: cel.y, width: w, height: h)
                    fileLayers[cel.layer].layer.reference = ReferenceImage(data: png, frame: frame)
                    continue
                }
                var full = PixelImage(width: width, height: height)
                full.pasteClipped(picture, at: cel.x, cel.y)
                guard !full.isEmpty else { continue }
                sprite.cels[key] = full
            case .link(let frame):
                guard frames.indices.contains(frame) else { continue }
                let source = CelKey(layer: layer.id, frame: frames[frame].id)
                guard let shared = sprite.cels[source] else { continue }
                sprite.cels[key] = shared
                let group = linkGroups[source] ?? UUID()
                linkGroups[source] = group
                sprite.links[source] = group
                sprite.links[key] = group
            case .tilemap(let columns, let rows, let tiles, let idMask, let xFlip, let yFlip, let dFlip):
                guard let tileset = fileLayers[cel.layer].layer.tileset else { continue }
                var full = PixelImage(width: width, height: height)
                var map = TileMap(columns: tileset.columns(width: width), rows: tileset.rows(height: height))
                let aligned = cel.x % tileset.tileWidth == 0 && cel.y % tileset.tileHeight == 0
                if !aligned { offGrid = true }
                for row in 0..<rows {
                    for column in 0..<columns {
                        let value = tiles[row * columns + column]
                        let index = Int(value & idMask)
                        guard index != 0, tileset.tiles.indices.contains(index) else { continue }
                        let tile = flipped(tileset.tiles[index], x: value & xFlip != 0, y: value & yFlip != 0, diagonal: value & dFlip != 0)
                        full.pasteClipped(tile, at: cel.x + column * tileset.tileWidth, cel.y + row * tileset.tileHeight)
                        let mc = cel.x / tileset.tileWidth + column, mr = cel.y / tileset.tileHeight + row
                        if aligned, tile == tileset.tiles[index], mc >= 0, mr >= 0, mc < map.columns, mr < map.rows { map[mc, mr] = index }
                    }
                }
                if !full.isEmpty { sprite.cels[key] = full }
                sprite.tilemaps[key] = map
            }
            if cel.opacity < 255, sprite.cels[key] != nil { sprite.celOpacity[key] = Double(cel.opacity) / 255 }
        }

        // Children first, then their group above them.
        var children: [UUID?: [Layer]] = [:]
        for entry in fileLayers { children[entry.layer.parent, default: []].append(entry.layer) }
        func flatten(_ parent: UUID?) -> [Layer] {
            (children[parent] ?? []).flatMap { $0.isGroup ? flatten($0.id) + [$0] : [$0] }
        }
        // A reference layer without an image can't be shown; it stays an empty layer.
        sprite.layers = flatten(nil).map { layer in
            var layer = layer
            if layer.reference?.data.isEmpty ?? false { layer.reference = nil }
            return layer
        }
        if sprite.layers.filter({ !$0.isGroup }).isEmpty { sprite.layers.append(Layer(name: L10n.string("Layer %d", 1))) }
        sprite.keepBackgroundAtBottom()

        let last = frames.count - 1
        sprite.tags = tags.compactMap { tag in
            var tag = tag
            tag.from = min(tag.from, last)
            tag.to = min(max(tag.to, tag.from), last)
            return tag
        }
        sprite.slices = slices.compactMap { slice in
            var slice = slice
            slice.keys = slice.keys.compactMap { key in
                guard let index = frameIndex(fromPlaceholder: key.frame), frames.indices.contains(index) else { return nil }
                var key = key
                key.frame = frames[index].id
                return key
            }
            return slice.keys.isEmpty ? nil : slice
        }
        // OpenPixel's tile grid starts at the sprite's corner. Cells whose tile couldn't be placed
        // get tiles of their own; when a whole tilemap sits off that grid, its tiles are rebuilt
        // from what it shows, reusing equal ones.
        if !sprite.tilemaps.isEmpty { sprite.syncTilemaps(mode: offGrid ? .auto : .stack) }
        sprite.normalizeLinks()
        return sprite
    }

    private static func readOldPalette(_ r: inout ByteReader) throws -> [PixelColor] {
        var colors: [PixelColor] = []
        var index = 0
        for _ in 0..<(try r.u16()) {
            index += Int(try r.u8())
            var count = Int(try r.u8())
            if count == 0 { count = 256 }
            for _ in 0..<count {
                let color = PixelColor(r: try r.u8(), g: try r.u8(), b: try r.u8())
                if colors.count <= index { colors += Array(repeating: .black, count: index - colors.count + 1) }
                colors[index] = color
                index += 1
            }
        }
        return colors
    }

    private static func flipped(_ tile: PixelImage, x: Bool, y: Bool, diagonal: Bool) -> PixelImage {
        guard x || y || diagonal else { return tile }
        var out = tile
        for ty in 0..<tile.height {
            for tx in 0..<tile.width {
                var sx = tx, sy = ty
                if diagonal, tile.width == tile.height { swap(&sx, &sy) }
                if x { sx = tile.width - 1 - sx }
                if y { sy = tile.height - 1 - sy }
                out[tx, ty] = tile[sx, sy]
            }
        }
        return out
    }

    private static func placeholder(for frame: Int) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(frame >> 24 & 0xFF), UInt8(frame >> 16 & 0xFF), UInt8(frame >> 8 & 0xFF), UInt8(frame & 0xFF)))
    }

    private static func frameIndex(fromPlaceholder id: UUID) -> Int? {
        let u = id.uuid
        guard [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11].allSatisfy({ $0 == 0 }) else { return nil }
        return Int(u.12) << 24 | Int(u.13) << 16 | Int(u.14) << 8 | Int(u.15)
    }

    private static let blendModes: [BlendMode?] = [
        .normal, .multiply, .screen, .overlay, .darken, .lighten, .colorDodge, .colorBurn, .hardLight, .softLight,
        .difference, .exclusion, nil, nil, nil, nil, .addition, .subtract, .divide
    ]

    /// Hue, saturation, color and luminosity aren't in OpenPixel; they read as normal.
    private static func blendMode(_ code: Int) -> BlendMode {
        blendModes.indices.contains(code) ? blendModes[code] ?? .normal : .normal
    }

    // MARK: Writing

    static func write(_ sprite: Sprite) throws -> Data {
        var w = ByteWriter()
        // Header (the file size is filled in at the end).
        w.u32(0)
        w.u16(0xA5E0)
        w.u16(sprite.frames.count)
        w.u16(sprite.width)
        w.u16(sprite.height)
        w.u16(32)
        w.u32(1 | 2)
        w.u16(sprite.frames.first?.duration ?? 100)
        w.zeros(8)
        w.u8(0)
        w.zeros(3)
        w.u16(min(sprite.palette.count, 65535))
        w.u8(sprite.pixelRatio.width)
        w.u8(sprite.pixelRatio.height)
        w.i16(sprite.grid.offsetX)
        w.i16(sprite.grid.offsetY)
        w.u16(sprite.grid.width)
        w.u16(sprite.grid.height)
        w.zeros(84)

        // The file lists each group before its children (OpenPixel keeps it above them).
        var fileLayers: [(layer: Layer, level: Int)] = []
        func walk(_ parent: UUID?, level: Int) {
            for layer in sprite.layers where layer.parent == parent {
                fileLayers.append((layer, level))
                if layer.isGroup { walk(layer.id, level: level + 1) }
            }
        }
        walk(nil, level: 0)
        let tilemapLayers = fileLayers.map(\.layer).filter(\.isTilemap)

        for (frameIndex, frame) in sprite.frames.enumerated() {
            var chunks: [ByteWriter] = []
            if frameIndex == 0 {
                chunks.append(paletteChunk(sprite.palette))
                for (index, layer) in tilemapLayers.enumerated() { chunks.append(try tilesetChunk(layer.tileset!, id: index, name: layer.name)) }
                for (layer, level) in fileLayers {
                    chunks.append(layerChunk(layer, level: level, tilesetIndex: tilemapLayers.firstIndex { $0.id == layer.id }))
                }
            }
            for (layerIndex, entry) in fileLayers.enumerated() where !entry.layer.isGroup {
                chunks += try celChunks(sprite, layer: entry.layer, layerIndex: layerIndex, frameIndex: frameIndex)
            }
            if frameIndex == 0 {
                if !sprite.tags.isEmpty {
                    chunks.append(tagsChunk(sprite.tags))
                    for tag in sprite.tags { chunks.append(colorUserData(tag.color)) }
                }
                for slice in sprite.slices {
                    chunks.append(sliceChunk(slice, frames: sprite.frames))
                    chunks.append(colorUserData(slice.color))
                }
            }

            let body = chunks.reduce(into: [UInt8]()) { $0 += $1.bytes }
            w.u32(16 + body.count)
            w.u16(0xF1FA)
            w.u16(min(chunks.count, 0xFFFF))
            w.u16(min(frame.duration, 65535))
            w.zeros(2)
            w.u32(chunks.count)
            w.bytes += body
        }
        w.set(u32: w.bytes.count, at: 0)
        return Data(w.bytes)
    }

    private static func chunk(_ type: Int, _ body: (inout ByteWriter) throws -> Void) rethrows -> ByteWriter {
        var content = ByteWriter()
        try body(&content)
        var c = ByteWriter()
        c.u32(6 + content.bytes.count)
        c.u16(type)
        c.bytes += content.bytes
        return c
    }

    private static func paletteChunk(_ palette: [PixelColor]) -> ByteWriter {
        chunk(0x2019) { c in
            let colors = palette.isEmpty ? [PixelColor.black] : Array(palette.prefix(65536))
            c.u32(colors.count)
            c.u32(0)
            c.u32(colors.count - 1)
            c.zeros(8)
            for color in colors {
                c.u16(0)
                c.u8(Int(color.r)); c.u8(Int(color.g)); c.u8(Int(color.b)); c.u8(Int(color.a))
            }
        }
    }

    private static func layerChunk(_ layer: Layer, level: Int, tilesetIndex: Int?) -> ByteWriter {
        chunk(0x2004) { c in
            var flags = 0
            if layer.isVisible { flags |= 1 }
            if !layer.isLocked { flags |= 2 }
            if layer.isBackground { flags |= 8 }
            if layer.isContinuous { flags |= 16 }
            if layer.isGroup && !layer.isExpanded { flags |= 32 }
            if layer.isReference { flags |= 64 }
            c.u16(flags)
            c.u16(layer.isGroup ? 1 : layer.isTilemap ? 2 : 0)
            c.u16(level)
            c.u16(0)
            c.u16(0)
            c.u16(blendModes.firstIndex(of: layer.blendMode) ?? 0)
            c.u8(Int((layer.opacity * 255).rounded()))
            c.zeros(3)
            c.string(layer.name)
            if let tilesetIndex { c.u32(tilesetIndex) }
        }
    }

    private static func tilesetChunk(_ tileset: Tileset, id: Int, name: String) throws -> ByteWriter {
        try chunk(0x2023) { c in
            c.u32(id)
            c.u32(2 | 4)
            c.u32(tileset.tiles.count)
            c.u16(tileset.tileWidth)
            c.u16(tileset.tileHeight)
            c.i16(1)
            c.zeros(14)
            c.string(name)
            var raw: [UInt8] = []
            for tile in tileset.tiles { raw += [UInt8](tile.rgbaData) }
            let compressed = try Zlib.deflate(raw)
            c.u32(compressed.count)
            c.bytes += compressed
        }
    }

    private static func celChunks(_ sprite: Sprite, layer: Layer, layerIndex: Int, frameIndex: Int) throws -> [ByteWriter] {
        let key = CelKey(layer: layer.id, frame: sprite.frames[frameIndex].id)
        func header(_ c: inout ByteWriter, x: Int, y: Int, type: Int) {
            c.u16(layerIndex)
            c.i16(x)
            c.i16(y)
            c.u8(Int(((sprite.celOpacity[key] ?? 1) * 255).rounded()))
            c.u16(type)
            c.i16(0)
            c.zeros(5)
        }

        if let reference = layer.reference {
            // Aseprite's reference layer is a cel at the image's own resolution, scaled by the Cel Extra bounds.
            guard frameIndex == 0,
                  let source = CGImageSourceCreateWithData(reference.data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let image = PixelImage(cgImage: cgImage) else { return [] }
            let celChunk = try chunk(0x2005) { c in
                header(&c, x: Int(reference.frame.minX.rounded(.down)), y: Int(reference.frame.minY.rounded(.down)), type: 2)
                c.u16(image.width)
                c.u16(image.height)
                c.bytes += try Zlib.deflate([UInt8](image.rgbaData))
            }
            let extra = chunk(0x2006) { c in
                c.u32(1)
                c.fixed(reference.frame.minX); c.fixed(reference.frame.minY)
                c.fixed(reference.frame.width); c.fixed(reference.frame.height)
                c.zeros(16)
            }
            return [celChunk, extra]
        }

        if layer.isTilemap, let map = sprite.tilemaps[key] {
            return [try chunk(0x2005) { c in
                header(&c, x: 0, y: 0, type: 3)
                c.u16(map.columns)
                c.u16(map.rows)
                c.u16(32)
                c.u32(0x1FFF_FFFF)
                c.u32(0x2000_0000)
                c.u32(0x4000_0000)
                c.u32(0x8000_0000)
                c.zeros(10)
                var raw = ByteWriter()
                for tile in map.tiles { raw.u32(tile) }
                c.bytes += try Zlib.deflate(raw.bytes)
            }]
        }

        guard let image = sprite.cels[key], let bounds = image.opaqueBounds else { return [] }
        // A linked cel points at the first frame that shows the same image.
        if let group = sprite.links[key],
           let first = sprite.frames.indices.first(where: { sprite.links[CelKey(layer: layer.id, frame: sprite.frames[$0].id)] == group }),
           first < frameIndex {
            return [chunk(0x2005) { c in
                header(&c, x: 0, y: 0, type: 1)
                c.u16(first)
            }]
        }
        let cropped = image.cropped(to: bounds)
        return [try chunk(0x2005) { c in
            header(&c, x: bounds.minX, y: bounds.minY, type: 2)
            c.u16(cropped.width)
            c.u16(cropped.height)
            c.bytes += try Zlib.deflate([UInt8](cropped.rgbaData))
        }]
    }

    private static func tagsChunk(_ tags: [FrameTag]) -> ByteWriter {
        chunk(0x2018) { c in
            c.u16(tags.count)
            c.zeros(8)
            for tag in tags {
                c.u16(tag.from)
                c.u16(tag.to)
                c.u8(AnimationDirection.allCases.firstIndex(of: tag.direction) ?? 0)
                c.u16(tag.repeatCount)
                c.zeros(6)
                c.u8(Int(tag.color.r)); c.u8(Int(tag.color.g)); c.u8(Int(tag.color.b))
                c.u8(0)
                c.string(tag.name)
            }
        }
    }

    private static func colorUserData(_ color: PixelColor) -> ByteWriter {
        chunk(0x2020) { c in
            c.u32(2)
            c.u8(Int(color.r)); c.u8(Int(color.g)); c.u8(Int(color.b)); c.u8(255)
        }
    }

    private static func sliceChunk(_ slice: Slice, frames: [Frame]) -> ByteWriter {
        let order = Dictionary(uniqueKeysWithValues: frames.enumerated().map { ($1.id, $0) })
        let keys = slice.keys.compactMap { key in order[key.frame].map { ($0, key) } }.sorted { $0.0 < $1.0 }
        let hasCenter = keys.contains { $0.1.center != nil }, hasPivot = keys.contains { $0.1.pivot != nil }
        return chunk(0x2022) { c in
            c.u32(keys.count)
            c.u32((hasCenter ? 1 : 0) | (hasPivot ? 2 : 0))
            c.u32(0)
            c.string(slice.name)
            for (frame, key) in keys {
                c.u32(frame)
                c.i32(key.bounds.minX)
                c.i32(key.bounds.minY)
                c.u32(key.bounds.width)
                c.u32(key.bounds.height)
                if hasCenter {
                    let center = key.center ?? PixelRect(minX: 0, minY: 0, maxX: key.bounds.width - 1, maxY: key.bounds.height - 1)
                    c.i32(center.minX); c.i32(center.minY); c.u32(center.width); c.u32(center.height)
                }
                if hasPivot {
                    let pivot = key.pivot ?? PixelPoint(x: 0, y: 0)
                    c.i32(pivot.x); c.i32(pivot.y)
                }
            }
        }
    }
}

// MARK: - Bytes

private struct ByteReader {
    private let bytes: [UInt8]
    var position = 0
    var count: Int { bytes.count }

    init(_ data: Data) { bytes = [UInt8](data) }

    private mutating func take(_ n: Int) throws -> ArraySlice<UInt8> {
        guard n >= 0, position + n <= bytes.count else { throw AsepriteFile.Failure.damaged }
        defer { position += n }
        return bytes[position..<(position + n)]
    }

    mutating func skip(_ n: Int) throws { _ = try take(n) }
    mutating func bytes(_ n: Int) throws -> [UInt8] { Array(try take(n)) }
    mutating func u8() throws -> UInt8 { try take(1).first! }

    mutating func u16() throws -> Int {
        let b = try take(2)
        return Int(b[b.startIndex]) | Int(b[b.startIndex + 1]) << 8
    }

    mutating func i16() throws -> Int16 { Int16(bitPattern: UInt16(try u16())) }

    mutating func u32() throws -> Int {
        let b = try take(4)
        return (0..<4).reduce(0) { $0 | Int(b[b.startIndex + $1]) << (8 * $1) }
    }

    mutating func i32() throws -> Int32 { Int32(bitPattern: UInt32(try u32())) }
    mutating func fixed() throws -> Double { Double(try i32()) / 65536 }
    mutating func string() throws -> String { String(decoding: try take(try u16()), as: UTF8.self) }
}

private struct ByteWriter {
    var bytes: [UInt8] = []

    mutating func u8(_ v: Int) { bytes.append(UInt8(truncatingIfNeeded: v)) }
    mutating func u16(_ v: Int) { u8(v); u8(v >> 8) }
    mutating func i16(_ v: Int) { u16(Int(UInt16(bitPattern: Int16(clamping: v)))) }
    mutating func u32(_ v: Int) { for i in 0..<4 { u8(v >> (8 * i)) } }
    mutating func i32(_ v: Int) { u32(Int(UInt32(bitPattern: Int32(clamping: v)))) }
    mutating func fixed(_ v: Double) { i32(Int((v * 65536).rounded())) }
    mutating func zeros(_ n: Int) { bytes += Array(repeating: 0, count: n) }

    mutating func string(_ s: String) {
        let utf8 = Array(s.utf8.prefix(65535))
        u16(utf8.count)
        bytes += utf8
    }

    mutating func set(u32 v: Int, at offset: Int) {
        for i in 0..<4 { bytes[offset + i] = UInt8(truncatingIfNeeded: v >> (8 * i)) }
    }
}

/// zlib streams (RFC 1950) around the raw DEFLATE the Compression framework speaks.
enum Zlib {
    static func deflate(_ input: [UInt8]) throws -> [UInt8] {
        var output = [UInt8](repeating: 0, count: input.count + input.count / 2 + 64)
        let size = input.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                compression_encode_buffer(dst.baseAddress!, dst.count, src.baseAddress!, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard size > 0 || input.isEmpty else { throw ExportError.encodingFailed }
        var result: [UInt8] = [0x78, 0x9C]
        result += output.prefix(size)
        let checksum = adler32(input)
        result += [UInt8(checksum >> 24 & 0xFF), UInt8(checksum >> 16 & 0xFF), UInt8(checksum >> 8 & 0xFF), UInt8(checksum & 0xFF)]
        return result
    }

    /// Inflates to exactly `size` bytes, the size the chunk says the image has.
    static func inflate(_ input: [UInt8], size: Int) throws -> [UInt8] {
        guard size > 0 else { return [] }
        guard input.count > 2 else { throw AsepriteFile.Failure.damaged }
        var output = [UInt8](repeating: 0, count: size)
        let written = input.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                // Skip the two-byte zlib header; the trailing checksum is ignored.
                compression_decode_buffer(dst.baseAddress!, size, src.baseAddress! + 2, src.count - 2, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw AsepriteFile.Failure.damaged }
        return output
    }

    private static func adler32(_ data: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for chunk in stride(from: 0, to: data.count, by: 5552) {
            for byte in data[chunk..<min(chunk + 5552, data.count)] {
                a += UInt32(byte)
                b += a
            }
            a %= 65521
            b %= 65521
        }
        return b << 16 | a
    }
}

extension PixelImage {
    /// Copies `image` with its top-left corner at (`dx`, `dy`), dropping what falls outside.
    mutating func pasteClipped(_ image: PixelImage, at dx: Int, _ dy: Int) {
        for y in max(0, -dy)..<min(image.height, height - dy) where y + dy >= 0 {
            for x in max(0, -dx)..<min(image.width, width - dx) where x + dx >= 0 {
                self[x + dx, y + dy] = image[x, y]
            }
        }
    }
}

extension UTType {
    /// Aseprite's sprites, `.aseprite` and `.ase` (declared in Info.plist).
    static let aseprite = UTType(importedAs: "org.aseprite.aseprite", conformingTo: .data)
}
