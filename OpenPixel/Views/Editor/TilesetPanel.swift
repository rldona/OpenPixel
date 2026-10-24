import SwiftUI

/// The active tilemap's tiles, in the side panel: pick the tile to place,
/// switch between drawing pixels and placing tiles, and choose the tileset mode.
struct TilesetPanel: View {
    @Bindable var document: SpriteDocument
    let tileset: Tileset
    @State private var exportURL: URL?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Tileset")
                Text(verbatim: "\(tileset.tiles.count - 1) · \(tileset.tileWidth)×\(tileset.tileHeight)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Spacer()
                if let exportURL {
                    ShareLink(item: exportURL) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel(Text("Export tileset"))
                }
            }
            Picker("Draw", selection: $document.tileDrawMode) {
                Label("Pixels", systemImage: "pencil").tag(TileDrawMode.pixels)
                Label("Tiles", systemImage: "square.grid.2x2").tag(TileDrawMode.tiles)
            }
            .pickerStyle(.segmented)
            if document.tileDrawMode == .pixels {
                Picker("Tileset mode", selection: $document.tilesetMode) {
                    Text("Manual").tag(TilesetMode.manual)
                    Text("Auto").tag(TilesetMode.auto)
                    Text("Stack").tag(TilesetMode.stack)
                }
                .pickerStyle(.segmented)
                Text(modeHint).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("The pencil places the selected tile, the eraser clears cells, the bucket fills connected cells and the eyedropper picks a tile.")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(tileset.tiles.indices, id: \.self) { index in
                    Button {
                        document.selectedTile = index
                        document.tileDrawMode = .tiles
                    } label: {
                        ZStack {
                            Checkerboard(cell: 4)
                            if index == 0 {
                                Image(systemName: "xmark").font(.system(size: 11)).foregroundStyle(Theme.muted)
                            } else if let image = tileset.tiles[index].makeCGImage() {
                                Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit()
                            }
                        }
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(document.selectedTile == index ? Theme.accent : Theme.border, lineWidth: document.selectedTile == index ? 2.5 : 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(index == 0 ? Text("Empty tile") : Text("Tile \(index)"))
                    .accessibilityAddTraits(document.selectedTile == index ? .isSelected : [])
                }
            }
        }
        .task(id: tileset) { exportURL = try? writeTileset() }
    }

    private var modeHint: LocalizedStringKey {
        switch document.tilesetMode {
        case .manual: "Editing a cell edits its tile, so every copy changes."
        case .auto: "Each edited cell gets a matching tile, new or reused; unused tiles go away."
        case .stack: "Each edited cell gets a new tile; existing tiles never change."
        }
    }

    private func writeTileset() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = (document.activeLayer?.name ?? "tileset").components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        let url = directory.appendingPathComponent("\(document.name)-\(name)-tileset.png")
        try Exporter.pngData(document.structure.tilesetImage(tileset)).write(to: url, options: .atomic)
        return url
    }
}
