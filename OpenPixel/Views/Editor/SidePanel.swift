import SwiftUI

struct SidePanel: View {
    @Bindable var document: SpriteDocument
    let preview: CGImage?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 8)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Vista previa")
                    PixelThumbnail(image: preview)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Color")
                    HStack(spacing: 12) {
                        ColorPicker(
                            "Color principal",
                            selection: Binding(get: { document.primary.color }, set: { document.primary = PixelColor($0) }),
                            supportsOpacity: true
                        )
                        .labelsHidden()
                        .scaleEffect(1.3)
                        .frame(width: 44, height: 44)
                        RoundedRectangle(cornerRadius: 12)
                            .fill(document.primary.color)
                            .frame(width: 52, height: 52)
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.15)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(document.primary.hex).font(.system(size: 15, weight: .medium, design: .monospaced))
                            Text("Secundario \(document.secondary.hex)").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack {
                        Button("Intercambiar", systemImage: "arrow.left.arrow.right") { document.swapColors() }
                        Spacer()
                        Button("A la paleta", systemImage: "plus") { document.addToPalette(document.primary) }
                            .disabled(document.sprite.palette.contains(document.primary))
                    }
                    .font(.system(size: 13, weight: .medium))
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Paleta")
                    LazyVGrid(columns: columns, spacing: 5) {
                        ForEach(Array(document.sprite.palette.enumerated()), id: \.offset) { index, color in
                            swatch(color, index: index)
                        }
                    }
                    Text("Toca un color para usarlo. Mantén pulsado para más opciones.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }

                VStack(spacing: 8) {
                    infoRow("Cel activa", "\(document.activeLayer?.name ?? "–") · \(document.activeFrameIndex + 1)")
                    infoRow("Opacidad de capa", "\(Int((document.activeLayer?.opacity ?? 1) * 100)) %")
                    infoRow("Animación", "\(document.sprite.totalDuration) ms")
                }
                .padding(14)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
            }
            .padding(16)
        }
        .background(Theme.panel)
        .overlay(alignment: .leading) { Rectangle().fill(Theme.border).frame(width: 1) }
    }

    private func swatch(_ color: PixelColor, index: Int) -> some View {
        Button {
            document.primary = color
            if document.tool == .eraser || document.tool == .eyedropper { document.select(.pencil) }
        } label: {
            RoundedRectangle(cornerRadius: 6)
                .fill(color.color)
                .frame(height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(color == document.primary ? Theme.text : .white.opacity(0.08), lineWidth: color == document.primary ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Color \(color.hex)")
        .contextMenu {
            Button("Usar como secundario", systemImage: "square.2.layers.3d.bottom.filled") { document.secondary = color }
            Button("Eliminar de la paleta", systemImage: "trash", role: .destructive) { document.removeFromPalette(at: index) }
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.muted)
            Spacer()
            Text(value)
        }
        .font(.system(size: 13))
    }
}
