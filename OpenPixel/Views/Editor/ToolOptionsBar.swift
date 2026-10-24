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
                toggle("Relleno", isOn: $document.shapeFilled)
            }
            if document.tool == .bucket {
                divider
                toggle("Contiguo", isOn: $document.fillContiguous)
            }
            if document.tool == .eyedropper {
                Text("Toca el lienzo para tomar un color")
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
                Button("Pincel más pequeño") { document.setBrushSize(document.brushSize - 1) }
                    .keyboardShortcut("[", modifiers: [])
                Button("Pincel más grande") { document.setBrushSize(document.brushSize + 1) }
                    .keyboardShortcut("]", modifiers: [])
            }
            .opacity(0)
            .accessibilityHidden(true)
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
            .accessibilityLabel("Pincel más pequeño")
            Text(verbatim: "\(document.brushSize) px")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(width: 44)
                .accessibilityLabel("Tamaño del pincel: \(document.brushSize) píxeles")
            Button { document.setBrushSize(document.brushSize + 1) } label: {
                Image(systemName: "plus").frame(width: 32, height: 34)
            }
            .disabled(document.brushSize >= SpriteDocument.maxBrushSize)
            .accessibilityLabel("Pincel más grande")
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
                .accessibilityLabel(shape == .square ? "Pincel cuadrado" : "Pincel redondo")
                .accessibilityAddTraits(document.brushShape == shape ? .isSelected : [])
            }
        }
    }

    private func toggle(_ title: String, isOn: Binding<Bool>) -> some View {
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
