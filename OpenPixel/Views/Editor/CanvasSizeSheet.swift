import SwiftUI

/// Edit > Canvas > Canvas size: a new width and height, in pixels or in grid
/// cells, growing or shrinking away from the anchor (Aseprite's Canvas Size).
/// https://www.aseprite.org/docs/canvas-size/
struct CanvasSizeSheet: View {
    let document: SpriteDocument
    @State private var width: Int
    @State private var height: Int
    @AppStorage("canvasSizeInCells") private var inCells = false
    @State private var anchor = (x: 1, y: 1)
    @Environment(\.dismiss) private var dismiss

    init(document: SpriteDocument) {
        self.document = document
        _width = State(initialValue: document.structure.width)
        _height = State(initialValue: document.structure.height)
    }

    private var grid: GridSettings { document.structure.grid }
    private var oldWidth: Int { document.structure.width }
    private var oldHeight: Int { document.structure.height }
    private var limit: Int { SpriteDocument.maxCanvasSize }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("In grid cells", isOn: $inCells)
                    if inCells {
                        Stepper(value: Binding(get: { width / grid.width }, set: { width = $0 * grid.width }), in: 1...max(1, limit / grid.width)) {
                            LabeledContent("Width") { Text("\(width / grid.width) cells") }
                        }
                        Stepper(value: Binding(get: { height / grid.height }, set: { height = $0 * grid.height }), in: 1...max(1, limit / grid.height)) {
                            LabeledContent("Height") { Text("\(height / grid.height) cells") }
                        }
                    } else {
                        Stepper(value: $width, in: 1...limit) {
                            LabeledContent("Width") { Text(verbatim: "\(width) px") }
                        }
                        Stepper(value: $height, in: 1...limit) {
                            LabeledContent("Height") { Text(verbatim: "\(height) px") }
                        }
                    }
                } footer: {
                    Text(verbatim: "\(oldWidth) × \(oldHeight) → \(width) × \(height) px")
                }

                Section {
                    HStack {
                        Spacer()
                        anchorGrid
                        Spacer()
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Anchor")
                } footer: {
                    Text("The drawing stays at the anchor; the canvas grows or shrinks on the other sides.")
                }
            }
            .navigationTitle(Text("Canvas size"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        document.resizeCanvas(width: width, height: height, anchor: anchor)
                        dismiss()
                    }
                    .disabled(width == oldWidth && height == oldHeight)
                }
            }
            .onChange(of: inCells, initial: true) { _, cells in
                // Whole cells: round the size to the grid.
                guard cells else { return }
                width = max(grid.width, (width + grid.width / 2) / grid.width * grid.width)
                height = max(grid.height, (height + grid.height / 2) / grid.height * grid.height)
            }
        }

    }

    /// Nine squares; the picked one is the anchor, arrows point where the canvas changes.
    private var anchorGrid: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let isOn = anchor.x == column && anchor.y == row
                        Button { anchor = (column, row) } label: {
                            Image(systemName: isOn ? "circle.fill" : arrow(column - anchor.x, row - anchor.y))
                                .font(.system(size: isOn ? 12 : 13, weight: .semibold))
                                .foregroundStyle(isOn ? Theme.onAccent : Theme.muted)
                                .frame(width: 44, height: 44)
                                .background(isOn ? Theme.accent : Theme.chip, in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(anchorName(column, row)))
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }
        }
    }

    /// The arrow from the anchor towards this square (only next to it).
    private func arrow(_ dx: Int, _ dy: Int) -> String {
        guard abs(dx) <= 1, abs(dy) <= 1 else { return "" }
        switch (dx, dy) {
        case (-1, -1): return "arrow.up.left"
        case (0, -1): return "arrow.up"
        case (1, -1): return "arrow.up.right"
        case (-1, 0): return "arrow.left"
        case (1, 0): return "arrow.right"
        case (-1, 1): return "arrow.down.left"
        case (0, 1): return "arrow.down"
        case (1, 1): return "arrow.down.right"
        default: return ""
        }
    }

    private func anchorName(_ column: Int, _ row: Int) -> LocalizedStringKey {
        switch (column, row) {
        case (0, 0): "Top left"
        case (1, 0): "Top"
        case (2, 0): "Top right"
        case (0, 1): "Left"
        case (1, 1): "Center"
        case (2, 1): "Right"
        case (0, 2): "Bottom left"
        case (1, 2): "Bottom"
        default: "Bottom right"
        }
    }
}
