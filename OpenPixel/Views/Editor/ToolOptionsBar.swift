import SwiftUI

/// Floating bar over the canvas with the active tool's options (Pixaki-style).
struct ToolOptionsBar: View {
    @Bindable var document: SpriteDocument

    var body: some View {
        HStack(spacing: 10) {
            Label(document.tool.title, systemImage: document.tool.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .fixedSize()

            if document.tool.usesBrush {
                divider
                brushSize
                brushShape
            }
            if document.tool == .pencil || document.tool == .eraser {
                divider
                toggle("Pixel-perfect", isOn: $document.pixelPerfect)
                    .disabled(document.brushSize > 1)
                    .opacity(document.brushSize > 1 ? 0.4 : 1)
            }
            if document.tool == .rectangle || document.tool == .ellipse {
                divider
                toggle("Fill", isOn: $document.shapeFilled)
            }
            if document.tool == .bucket {
                divider
                toggle("Contiguous", isOn: $document.fillContiguous)
            }
            if document.tool == .eyedropper {
                Text("Tap the canvas to pick a color")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize()
            }
            if document.tool.isSelection {
                divider
                selectionModes
                if document.hasSelection, document.selectionMode == .replace, document.tool != .magicWand {
                    Text("Drag inside to move")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize()
                }
            }
            if document.tool == .magicWand {
                divider
                tolerance
                toggle("Contiguous", isOn: $document.wandContiguous)
                toggle("All layers", isOn: $document.wandSampleAllLayers)
            }
            if document.tool == .text {
                divider
                textOptions
            }
            if document.tool == .move {
                Text("Drag to move the selection or the layer content")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Theme.panel.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        .background {
            // Common shortcut for brush size in drawing apps.
            Group {
                Button("Smaller brush") { document.setBrushSize(document.brushSize - 1) }
                    .keyboardShortcut("[", modifiers: [])
                Button("Bigger brush") { document.setBrushSize(document.brushSize + 1) }
                    .keyboardShortcut("]", modifiers: [])
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    /// Replace / add / subtract / intersect. On a keyboard-less iPad these
    /// replace Aseprite's Shift and Alt modifiers.
    private var selectionModes: some View {
        HStack(spacing: 2) {
            ForEach(SelectionMode.allCases) { mode in
                Button { document.selectionMode = mode } label: {
                    Image(systemName: icon(for: mode))
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 36, height: 30)
                        .foregroundStyle(document.selectionMode == mode ? Theme.onAccent : Theme.text)
                        .background(document.selectionMode == mode ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(title(for: mode)))
                .accessibilityAddTraits(document.selectionMode == mode ? .isSelected : [])
            }
        }
    }

    private func icon(for mode: SelectionMode) -> String {
        switch mode {
        case .replace: "square.dashed"
        case .add: "plus.square.dashed"
        case .subtract: "minus.square"
        case .intersect: "square.on.square.intersection.dashed"
        }
    }

    private func title(for mode: SelectionMode) -> LocalizedStringKey {
        switch mode {
        case .replace: "Replace selection"
        case .add: "Add to selection"
        case .subtract: "Subtract from selection"
        case .intersect: "Intersect selection"
        }
    }

    private var tolerance: some View {
        HStack(spacing: 2) {
            Text("Tolerance").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).fixedSize()
            Button { document.wandTolerance = max(0, document.wandTolerance - 8) } label: {
                Image(systemName: "minus").frame(width: 30, height: 34)
            }
            .accessibilityLabel(Text("Lower tolerance"))
            Text(verbatim: "\(document.wandTolerance)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(width: 34)
            Button { document.wandTolerance = min(255, document.wandTolerance + 8) } label: {
                Image(systemName: "plus").frame(width: 30, height: 34)
            }
            .accessibilityLabel(Text("Higher tolerance"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
    }

    /// Font, size and outline; the rest is in the sheet that opens on tapping the canvas.
    private var textOptions: some View {
        HStack(spacing: 10) {
            Menu {
                TextFontPicker(style: $document.textStyle)
            } label: {
                HStack(spacing: 4) {
                    Text(verbatim: document.textStyle.fontName)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text)
                .fixedSize()
            }
            .accessibilityLabel(Text("Font"))
            HStack(spacing: 2) {
                Button { adjustTextSize(-1) } label: { Image(systemName: "minus").frame(width: 30, height: 34) }
                    .accessibilityLabel(Text("Smaller text"))
                Text(verbatim: document.textStyle.sizeLabel)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .frame(minWidth: 40)
                Button { adjustTextSize(1) } label: { Image(systemName: "plus").frame(width: 30, height: 34) }
                    .accessibilityLabel(Text("Bigger text"))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.text)
            toggle("Outline", isOn: $document.textStyle.outline)
            Text("Tap the canvas to write")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize()
        }
    }

    private func adjustTextSize(_ direction: Int) {
        if case .pixel = document.textStyle.font {
            document.textStyle.scale = min(8, max(1, document.textStyle.scale + direction))
        } else {
            document.textStyle.pointSize = min(128, max(6, document.textStyle.pointSize + 2 * direction))
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(width: 1, height: 22)
    }

    private var brushSize: some View {
        HStack(spacing: 2) {
            Button { document.setBrushSize(document.brushSize - 1) } label: {
                Image(systemName: "minus").frame(width: 32, height: 34)
            }
            .disabled(document.brushSize <= 1)
            .accessibilityLabel(Text("Smaller brush"))
            Text(verbatim: "\(document.brushSize) px")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(width: 44)
                .accessibilityLabel(Text("Brush size: \(document.brushSize) pixels"))
            Button { document.setBrushSize(document.brushSize + 1) } label: {
                Image(systemName: "plus").frame(width: 32, height: 34)
            }
            .disabled(document.brushSize >= SpriteDocument.maxBrushSize)
            .accessibilityLabel(Text("Bigger brush"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
    }

    private var brushShape: some View {
        HStack(spacing: 2) {
            ForEach(BrushShape.allCases) { shape in
                Button { document.brushShape = shape } label: {
                    Image(systemName: shape == .square ? "square.fill" : "circle.fill")
                        .font(.system(size: 12))
                        .frame(width: 32, height: 30)
                        .foregroundStyle(document.brushShape == shape ? Theme.onAccent : Theme.muted)
                        .background(document.brushShape == shape ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(shape == .square ? Text("Square brush") : Text("Round brush"))
                .accessibilityAddTraits(document.brushShape == shape ? .isSelected : [])
            }
        }
    }

    private func toggle(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn.wrappedValue ? Theme.accent : Theme.muted)
                Text(title).foregroundStyle(Theme.text)
            }
            .font(.system(size: 13, weight: .medium))
            .fixedSize()
            .frame(height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }
}
