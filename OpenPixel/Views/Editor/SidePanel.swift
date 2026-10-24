import SwiftUI

struct SidePanel: View {
    @Bindable var document: SpriteDocument

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 8)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Preview")
                    // Updates when a stroke is committed, not on every stroke sample.
                    PixelThumbnail(image: document.sprite.composite(frameIndex: document.activeFrameIndex).makeCGImage())
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Color")
                    HStack(spacing: 12) {
                        ColorPicker(
                            "Primary color",
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
                            Text("Secondary \(document.secondary.hex)").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack {
                        Button("Swap", systemImage: "arrow.left.arrow.right") { document.swapColors() }
                        Spacer()
                        Button("Add to palette", systemImage: "plus") { document.addToPalette(document.primary) }
                            .disabled(document.sprite.palette.contains(document.primary))
                    }
                    .font(.system(size: 13, weight: .medium))
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Palette")
                    LazyVGrid(columns: columns, spacing: 5) {
                        ForEach(Array(document.sprite.palette.enumerated()), id: \.offset) { index, color in
                            swatch(color, index: index)
                        }
                    }
                    Text("Tap a color to use it. Touch and hold for more options.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }

                VStack(spacing: 8) {
                    infoRow("Active cel", "\(document.activeLayer?.name ?? "–") · \(document.activeFrameIndex + 1)")
                    infoRow("Layer opacity", "\(Int((document.activeLayer?.opacity ?? 1) * 100)) %")
                    infoRow("Animation", "\(document.sprite.totalDuration) ms")
                }
                .padding(14)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
            }
            .padding(16)
        }
        // Background and divider run under the home indicator; the content stays in the safe area.
        .background {
            HStack(spacing: 0) {
                Rectangle().fill(Theme.border).frame(width: 1)
                Theme.panel
            }
            .ignoresSafeArea(edges: .bottom)
        }
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
        .accessibilityLabel(Text("Color \(color.hex)"))
        .contextMenu {
            Button("Use as secondary", systemImage: "square.2.layers.3d.bottom.filled") { document.secondary = color }
            Button("Remove from palette", systemImage: "trash", role: .destructive) { document.removeFromPalette(at: index) }
        }
    }

    private func infoRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.muted)
            Spacer()
            Text(verbatim: value)
        }
        .font(.system(size: 13))
    }
}
