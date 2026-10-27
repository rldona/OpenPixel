import SwiftUI

/// Edit > Replace Color (⇧R): swaps one color for another in the active cel
/// or in every cel, inside the selection when there is one. A window like
/// Hue/Saturation's, so the canvas stays in view.
/// https://www.aseprite.org/docs/replace-color/
struct ReplaceColorPanel: View {
    let document: SpriteDocument
    /// The space it can be dragged in.
    let area: CGSize
    /// How far its starting place is from the area's right edge.
    let trailingInset: CGFloat
    @State private var from: PixelColor
    @State private var to: PixelColor
    @State private var tolerance = 0.0
    @State private var everyCel = false
    @State private var editingFrom = false
    @State private var editingTo = false

    init(document: SpriteDocument, area: CGSize, trailingInset: CGFloat) {
        self.document = document
        self.area = area
        self.trailingInset = trailingInset
        _from = State(initialValue: document.primary)
        _to = State(initialValue: document.secondary)
    }

    var body: some View {
        FloatingWindow(Text("Replace color"), id: "replaceColor", area: area, trailingInset: trailingInset, approximateHeight: 330) {
            Button { swap(&from, &to) } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.muted)
            .accessibilityLabel(Text("Swap"))
        } content: {
            VStack(spacing: 8) {
                colorRow("From", color: from, isEditing: $editingFrom) {
                    ColorEditor(color: $from, palette: document.sprite.palette)
                }
                colorRow("To", color: to, isEditing: $editingTo) {
                    ColorEditor(color: $to, palette: document.sprite.palette)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Tolerance").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(verbatim: "\(Int(tolerance))")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
                Slider(value: $tolerance, in: 0...255, step: 1).tint(Theme.accent)
                Text("0 replaces only the exact color; higher values also replace similar ones.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker("Where", selection: $everyCel) {
                Text("Current cel").tag(false)
                Text("Every cel").tag(true)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Button { document.isReplacingColor = false } label: {
                    Text("Close").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 10))
                .keyboardShortcut(.cancelAction)
                // Stays open, so another color can be replaced right after.
                Button {
                    let count = document.replaceColor(from, with: to, tolerance: Int(tolerance), everyCel: everyCel)
                    if count == 0, document.notice == nil {
                        document.notice = L10n.string("No pixels of that color")
                    }
                } label: {
                    Text("Replace").fontWeight(.semibold).foregroundStyle(Theme.onAccent).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                .keyboardShortcut(.defaultAction)
            }
            .font(.system(size: 15))
        }
    }

    private func colorRow(_ title: LocalizedStringKey, color: PixelColor, isEditing: Binding<Bool>, @ViewBuilder editor: @escaping () -> some View) -> some View {
        Button { isEditing.wrappedValue = true } label: {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                Spacer()
                Text(verbatim: color.hex).font(.system(size: 13, design: .monospaced)).foregroundStyle(Theme.muted)
                ZStack {
                    Checkerboard(cell: 5)
                    color.color
                }
                .frame(width: 36, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 40)
            .background(Theme.chip, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: isEditing) {
            editor().presentationCompactAdaptation(.popover)
        }
    }
}
