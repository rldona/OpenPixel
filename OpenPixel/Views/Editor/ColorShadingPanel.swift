import SwiftUI

/// Ramps around a base color, like the Color Shading extension for Aseprite:
/// tap a color to use it, touch and hold for more. A window like Hue/Saturation's.
struct ColorShadingPanel: View {
    @Bindable var document: SpriteDocument
    /// The space it can be dragged in.
    let area: CGSize
    /// How far its starting place is from the area's right edge.
    let trailingInset: CGFloat
    /// The base follows the primary color until a ramp color is picked, so the
    /// ramps stay put while choosing from them.
    @State private var base: PixelColor?
    /// Shade alone by default; the other ramps on request (remembered).
    @AppStorage("colorShadingShowsAll") private var showsAll = false

    var body: some View {
        let base = base ?? document.primary
        FloatingWindow(Text("Color shading"), id: "colorShading", area: area, trailingInset: trailingInset, approximateHeight: showsAll ? 300 : 120) {
            HStack(spacing: 2) {
                if self.base != nil {
                    headerButton("arrow.triangle.2.circlepath", label: "Follow color") { self.base = nil }
                }
                headerButton("xmark", label: "Close") { document.isShowingColorShading = false }
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                row("Shade", ColorShading.shades(base), base: base)
                if showsAll {
                    row("Lightness", ColorShading.lights(base), base: base)
                    row("Saturation", ColorShading.saturations(base), base: base)
                    row("Hue", ColorShading.hues(base), base: base)
                }
                Button {
                    withAnimation(.snappy(duration: 0.2)) { showsAll.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(showsAll ? "Fewer" : "Lightness, saturation and hue")
                        Image(systemName: showsAll ? "chevron.up" : "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accentText)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func headerButton(_ systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.muted)
        .accessibilityLabel(Text(label))
    }

    private func row(_ title: LocalizedStringKey, _ colors: [PixelColor], base: PixelColor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
            HStack(spacing: 0) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                    Button {
                        if self.base == nil { self.base = base }
                        document.primary = color
                    } label: {
                        ZStack {
                            Checkerboard(cell: 5)
                            color.color
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .overlay {
                            if color == document.primary {
                                Rectangle().strokeBorder(Theme.panel, lineWidth: 2).padding(1)
                                    .overlay(Rectangle().strokeBorder(Theme.text, lineWidth: 1))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Use as secondary", systemImage: "square.on.square") { document.secondary = color }
                        Button("Add to palette", systemImage: "plus.square") { document.addToPalette(color) }
                    }
                    .accessibilityLabel(Text(verbatim: color.hex))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        }
    }
}
