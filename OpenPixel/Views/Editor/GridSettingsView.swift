import SwiftUI

/// View > Grid Settings: the size and offset of the sprite's grid.
struct GridSettingsView: View {
    @Bindable var document: SpriteDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Grid settings").font(.system(size: 15, weight: .semibold))
            HStack(spacing: 10) {
                NumberChip(title: "Width", value: binding(\.width), range: 1...max(1, document.sprite.width), unit: "px", presets: [4, 8, 16, 24, 32, 48, 64])
                NumberChip(title: "Height", value: binding(\.height), range: 1...max(1, document.sprite.height), unit: "px", presets: [4, 8, 16, 24, 32, 48, 64])
            }
            HStack(spacing: 10) {
                NumberChip(title: "Offset X", value: binding(\.offsetX), range: 0...max(0, document.sprite.grid.width - 1), unit: "px")
                NumberChip(title: "Offset Y", value: binding(\.offsetY), range: 0...max(0, document.sprite.grid.height - 1), unit: "px")
            }
            HStack(spacing: 8) {
                PillToggle(title: "Show the grid", isOn: $document.showTileGrid)
                PillToggle(title: "Snap to grid", isOn: $document.snapToGrid)
            }
            Text("Marquees snap to whole cells and moves go cell by cell. The paint bucket can stop at the grid lines, and tilemaps use this size.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 340)
        .background(Theme.panel)
    }

    private func binding(_ field: WritableKeyPath<GridSettings, Int>) -> Binding<Int> {
        Binding(get: { document.sprite.grid[keyPath: field] }, set: {
            var grid = document.sprite.grid
            grid[keyPath: field] = $0
            document.setGrid(grid)
        })
    }
}
