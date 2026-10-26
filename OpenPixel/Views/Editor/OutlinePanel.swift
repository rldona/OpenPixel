import SwiftUI

/// Aseprite's Outline window: the canvas shows the outline while the options
/// change. Apply makes it one undo step.
struct OutlinePanel: View {
    let document: SpriteDocument
    /// The space it can be dragged in.
    let area: CGSize
    /// How far its starting place is from the area's right edge.
    let trailingInset: CGFloat
    @State private var place = OutlineEffect.Place.outside
    @State private var matrix = OutlineEffect.circle
    @State private var usesSecondary = false
    @State private var backgroundIsSecondary = false
    @State private var tiled = false
    @State private var everyCel = false

    /// Colors follow the primary and secondary while the window is open.
    private var effect: OutlineEffect {
        var color = usesSecondary ? document.secondary : document.primary
        if color.a == 0 { color.a = 255 }
        return OutlineEffect(
            place: place,
            matrix: matrix,
            color: color,
            background: backgroundIsSecondary ? document.secondary : .clear,
            tiled: tiled
        )
    }

    var body: some View {
        FloatingWindow(Text("Outline"), id: "outline", area: area, trailingInset: trailingInset, approximateHeight: 530) {
            EmptyView()
        } content: {
            Picker("Place", selection: $place) {
                Text("Outside").tag(OutlineEffect.Place.outside)
                Text("Inside").tag(OutlineEffect.Place.inside)
            }
            .pickerStyle(.segmented)

            HStack(alignment: .top, spacing: 14) {
                // The four shapes, then the neighbours one by one.
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 6), count: 2), spacing: 6) {
                    shape("Circle", OutlineEffect.circle)
                    shape("Square", OutlineEffect.square)
                    shape("Horizontal", OutlineEffect.horizontal)
                    shape("Vertical", OutlineEffect.vertical)
                }
                Spacer(minLength: 0)
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 4), count: 3), spacing: 4) {
                    ForEach(0..<9, id: \.self) { i in neighbour(i) }
                }
            }

            colorRow(Text("Outline color")) {
                swatchButton(Text("Primary"), color: document.primary, isOn: !usesSecondary) { usesSecondary = false }
                swatchButton(Text("Secondary"), color: document.secondary, isOn: usesSecondary) { usesSecondary = true }
            }
            colorRow(Text("Background")) {
                swatchButton(Text("Transparent"), color: .clear, isOn: !backgroundIsSecondary) { backgroundIsSecondary = false }
                swatchButton(Text("Secondary"), color: document.secondary, isOn: backgroundIsSecondary) { backgroundIsSecondary = true }
            }

            Toggle("Tiled", isOn: $tiled)
                .font(.system(size: 14))
                .tint(Theme.accent)

            Picker("Where", selection: $everyCel) {
                document.timelineRange == nil ? Text("Current cel").tag(false) : Text("Selected cels").tag(false)
                Text("Every cel").tag(true)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Button { document.endOutline(apply: nil, everyCel: everyCel) } label: {
                    Text("Cancel").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 10))
                .keyboardShortcut(.cancelAction)
                Button { document.endOutline(apply: effect, everyCel: everyCel) } label: {
                    Text("Apply").fontWeight(.semibold).foregroundStyle(Theme.onAccent).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                .keyboardShortcut(.defaultAction)
            }
            .font(.system(size: 15))
        }
        // A short pause between changes keeps big sprites responsive.
        .task(id: Preview(effect: effect, everyCel: everyCel)) {
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            document.previewOutline(effect, everyCel: everyCel)
        }
    }

    private struct Preview: Hashable {
        var effect: OutlineEffect
        var everyCel: Bool
    }

    /// A preset: a small picture of the neighbours it takes.
    private func shape(_ title: LocalizedStringKey, _ preset: [Bool]) -> some View {
        let isOn = matrix == preset
        return Button { matrix = preset } label: {
            Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                ForEach(0..<3, id: \.self) { row in
                    GridRow {
                        ForEach(0..<3, id: \.self) { column in
                            let i = row * 3 + column
                            Rectangle()
                                .fill(i == 4 ? Theme.muted.opacity(0.5) : (preset[i] ? (isOn ? Theme.accent : Theme.text) : Theme.muted.opacity(0.15)))
                                .frame(width: 7, height: 7)
                        }
                    }
                }
            }
            .frame(width: 40, height: 40)
            .background(isOn ? Theme.accentSoft : Theme.chip, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// One neighbour of the 3×3 matrix; the middle is the pixel itself.
    private func neighbour(_ i: Int) -> some View {
        let isOn = matrix[i]
        return Button { matrix[i].toggle() } label: {
            RoundedRectangle(cornerRadius: 3)
                .fill(i == 4 ? Theme.muted.opacity(0.3) : (isOn ? Theme.accent : Theme.muted.opacity(0.15)))
                .frame(width: 14, height: 14)
                .frame(width: 32, height: 32)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(i == 4)
        .accessibilityLabel(Text("Neighbour \(i + 1)"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func colorRow(_ title: Text, @ViewBuilder buttons: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            title
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.muted)
            HStack(spacing: 6) { buttons() }
        }
    }

    private func swatchButton(_ title: Text, color: PixelColor, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                ZStack {
                    Checkerboard(cell: 4)
                    color.color
                }
                .frame(width: 14, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Theme.border))
                title.lineLimit(1).minimumScaleFactor(0.75)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isOn ? Theme.accentText : Theme.text)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(isOn ? Theme.accentSoft : Theme.chip, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
