import Foundation

/// The tiles of a tilemap layer. Tile 0 is always the empty tile, like
/// Aseprite's. https://www.aseprite.org/docs/tilemap/
struct Tileset: Codable, Equatable, Sendable {
    var tileWidth: Int
    var tileHeight: Int
    /// tiles[0] is the empty tile.
    var tiles: [PixelImage]

    init(tileWidth: Int, tileHeight: Int) {
        self.tileWidth = tileWidth
        self.tileHeight = tileHeight
        tiles = [PixelImage(width: tileWidth, height: tileHeight)]
    }

    func columns(width: Int) -> Int { (width + tileWidth - 1) / tileWidth }
    func rows(height: Int) -> Int { (height + tileHeight - 1) / tileHeight }
}

/// Which tile each cell of a tilemap cel shows, row by row.
struct TileMap: Codable, Equatable, Sendable {
    var columns: Int
    var rows: Int
    var tiles: [Int]

    init(columns: Int, rows: Int) {
        self.columns = columns
        self.rows = rows
        tiles = Array(repeating: 0, count: columns * rows)
    }

    subscript(column: Int, row: Int) -> Int {
        get { tiles[row * columns + column] }
        set { tiles[row * columns + column] = newValue }
    }
}

/// What drawing pixels on a tilemap does to its tiles (Aseprite's tileset modes).
enum TilesetMode: String, CaseIterable, Identifiable {
    /// Edits the tile itself, so every cell showing it changes.
    case manual
    /// Makes or reuses a tile for each edited cell and drops tiles nothing uses.
    case auto
    /// Every edited cell gets a new tile; existing ones are never touched.
    case stack

    var id: String { rawValue }
}

/// Whether drawing on a tilemap paints pixels or places whole tiles.
enum TileDrawMode: String, CaseIterable, Identifiable {
    case pixels, tiles
    var id: String { rawValue }
}

extension Sprite {
    /// The tile-sized cut of `image` at a cell; pixels past the sprite's edge are empty.
    static func cell(of image: PixelImage?, column: Int, row: Int, in tileset: Tileset) -> PixelImage {
        var tile = PixelImage(width: tileset.tileWidth, height: tileset.tileHeight)
        guard let image else { return tile }
        let x0 = column * tileset.tileWidth, y0 = row * tileset.tileHeight
        for y in 0..<tileset.tileHeight where y0 + y < image.height {
            for x in 0..<tileset.tileWidth where x0 + x < image.width {
                tile[x, y] = image[x0 + x, y0 + y]
            }
        }
        return tile
    }

    /// Draws `tile` into `image` at a cell, clipped to the image.
    static func draw(_ tile: PixelImage, into image: inout PixelImage, column: Int, row: Int) {
        let x0 = column * tile.width, y0 = row * tile.height
        for y in 0..<tile.height where y0 + y < image.height {
            for x in 0..<tile.width where x0 + x < image.width {
                image[x0 + x, y0 + y] = tile[x, y]
            }
        }
    }

    /// The image a tilemap cel shows.
    func render(_ map: TileMap, with tileset: Tileset) -> PixelImage {
        var image = PixelImage(width: width, height: height)
        for row in 0..<map.rows {
            for column in 0..<map.columns where map[column, row] != 0 {
                let index = map[column, row]
                guard tileset.tiles.indices.contains(index) else { continue }
                Self.draw(tileset.tiles[index], into: &image, column: column, row: row)
            }
        }
        return image
    }

    /// Brings tilemaps up to date with their cels' pixels after an edit.
    /// Each cel image is the truth; cells that no longer match their tile
    /// were edited, and `mode` decides what happens to the tileset.
    mutating func syncTilemaps(mode: TilesetMode) {
        for li in layers.indices {
            guard var tileset = layers[li].tileset else { continue }
            let layerID = layers[li].id
            let columns = tileset.columns(width: width), rows = tileset.rows(height: height)
            var modified: Set<Int> = []
            // Every distinct tile, for reuse in auto mode (and to find the empty tile).
            var lookup: [[PixelColor]: Int] = [:]
            if mode == .auto {
                for (i, tile) in tileset.tiles.enumerated() where lookup[tile.pixels] == nil { lookup[tile.pixels] = i }
            }
            func indexFor(_ tile: PixelImage) -> Int {
                if tile.isEmpty { return 0 }
                if mode == .auto, let i = lookup[tile.pixels] { return i }
                tileset.tiles.append(tile)
                lookup[tile.pixels] = tileset.tiles.count - 1
                return tileset.tiles.count - 1
            }
            var maps: [UUID: TileMap] = [:]
            for frame in frames {
                let key = CelKey(layer: layerID, frame: frame.id)
                let image = cels[key]
                var map = tilemaps[key] ?? TileMap(columns: columns, rows: rows)
                if map.columns != columns || map.rows != rows { map = TileMap(columns: columns, rows: rows) }
                for row in 0..<rows {
                    for column in 0..<columns {
                        let index = map[column, row]
                        // Other copies of a tile edited in this pass still show its old
                        // pixels; they're redrawn below, not taken as edits.
                        if modified.contains(index) { continue }
                        let current = Self.cell(of: image, column: column, row: row, in: tileset)
                        let expected = tileset.tiles.indices.contains(index) ? tileset.tiles[index] : tileset.tiles[0]
                        guard current != expected else { continue }
                        if mode == .manual, index != 0, tileset.tiles.indices.contains(index) {
                            // Manual: the tile itself changes, everywhere it's used.
                            tileset.tiles[index] = current
                            modified.insert(index)
                        } else {
                            map[column, row] = indexFor(current)
                        }
                    }
                }
                maps[frame.id] = map
            }
            if mode == .auto {
                // Drop tiles no cel uses, keeping the order of the rest.
                var used: Set<Int> = [0]
                for map in maps.values { used.formUnion(map.tiles) }
                if used.count < tileset.tiles.count {
                    var remap: [Int: Int] = [:]
                    var kept: [PixelImage] = []
                    for (i, tile) in tileset.tiles.enumerated() where used.contains(i) {
                        remap[i] = kept.count
                        kept.append(tile)
                    }
                    tileset.tiles = kept
                    for id in maps.keys { maps[id]!.tiles = maps[id]!.tiles.map { remap[$0] ?? 0 } }
                }
            }
            for (frameID, map) in maps {
                let key = CelKey(layer: layerID, frame: frameID)
                tilemaps[key] = map
                guard !modified.isEmpty, map.tiles.contains(where: modified.contains) else { continue }
                // Manual mode: other cells showing an edited tile show the new pixels.
                var image = cels[key] ?? PixelImage(width: width, height: height)
                for row in 0..<map.rows {
                    for column in 0..<map.columns where modified.contains(map[column, row]) {
                        Self.draw(tileset.tiles[map[column, row]], into: &image, column: column, row: row)
                    }
                }
                cels[key] = image.isEmpty ? nil : image
            }
            layers[li].tileset = tileset
        }
        // Maps of cels that are gone, or of layers that aren't tilemaps anymore.
        if !tilemaps.isEmpty {
            let tilemapLayers = Set(layers.filter { $0.tileset != nil }.map(\.id)), frameIDs = Set(frames.map(\.id))
            tilemaps = tilemaps.filter { tilemapLayers.contains($0.key.layer) && frameIDs.contains($0.key.frame) }
        }
    }

    /// The tileset laid out in a row (for export), tile 0 left out.
    func tilesetImage(_ tileset: Tileset) -> PixelImage {
        let tiles = tileset.tiles.dropFirst()
        var sheet = PixelImage(width: max(1, tiles.count) * tileset.tileWidth, height: tileset.tileHeight)
        for (i, tile) in tiles.enumerated() { Self.draw(tile, into: &sheet, column: i, row: 0) }
        return sheet
    }
}
