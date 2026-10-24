import SwiftUI

/// The slice tool's options: which slice, and the active one's name,
/// color, bounds, 9-slice centre and pivot.
struct SliceOptions: View {
    @Bindable var document: SpriteDocument
    @State private var showing = false

    var body: some View {
        HStack(spacing: 10) {
            if let slice = activeSlice {
                Button { showing = true } label: {
                    HStack(spacing: 6) {
                        Circle().fill(slice.color.color).frame(width: 12, height: 12)
                        Text(verbatim: slice.name)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Theme.chip, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Slice properties"))
                .popover(isPresented: $showing) {
                    SliceProperties(document: document, slice: slice).presentationCompactAdaptation(.popover)
                }
                Button { document.deleteSlice(slice.id) } label: {
                    Image(systemName: "trash").frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.text)
                .accessibilityLabel(Text("Delete slice"))
                .keyboardShortcut(.delete, modifiers: [])
            }
            ViewThatFits(in: .horizontal) {
                Text(activeSlice == nil ? "Drag to draw a slice" : "Drag an edge to resize, inside to move")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize()
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }

    private var activeSlice: Slice? { document.structure.slices.first { $0.id == document.activeSliceID } }
}

private struct SliceProperties: View {
    @Bindable var document: SpriteDocument
    let slice: Slice
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit { document.renameSlice(slice.id, to: name) }
            HStack(spacing: 8) {
                ForEach(Slice.colors, id: \.self) { color in
                    Button { document.setSliceColor(slice.id, color) } label: {
                        Circle().fill(color.color).frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(Theme.text, lineWidth: currentColor == color ? 2 : 0).padding(-3))
                    }
                    .buttonStyle(.plain)
                }
            }
            if let key = document.activeSliceKey {
                section("Bounds") {
                    HStack(spacing: 8) {
                        chip("X", key.bounds.minX, -4096...4096) { k, v in k.bounds = k.bounds.offsetBy(dx: v - k.bounds.minX, dy: 0) }
                        chip("Y", key.bounds.minY, -4096...4096) { k, v in k.bounds = k.bounds.offsetBy(dx: 0, dy: v - k.bounds.minY) }
                    }
                    HStack(spacing: 8) {
                        chip("Width", key.bounds.width, 1...4096) { k, v in k.bounds.maxX = k.bounds.minX + v - 1 }
                        chip("Height", key.bounds.height, 1...4096) { k, v in k.bounds.maxY = k.bounds.minY + v - 1 }
                    }
                }
                section("9-slice") {
                    PillToggle(title: "Center area", isOn: Binding(get: { key.center != nil }, set: { on in
                        document.editActiveSlice { k in
                            k.center = on ? PixelRect(minX: k.bounds.width / 3, minY: k.bounds.height / 3,
                                                      maxX: max(k.bounds.width / 3, k.bounds.width * 2 / 3 - 1),
                                                      maxY: max(k.bounds.height / 3, k.bounds.height * 2 / 3 - 1)) : nil
                        }
                    }))
                    if let c = key.center {
                        HStack(spacing: 8) {
                            chip("Left", c.minX, 0...max(0, key.bounds.width - 1)) { k, v in if var c = k.center { c.minX = min(v, c.maxX); k.center = c } }
                            chip("Right", key.bounds.width - 1 - c.maxX, 0...max(0, key.bounds.width - 1)) { k, v in
                                if var c = k.center { c.maxX = max(c.minX, k.bounds.width - 1 - v); k.center = c }
                            }
                        }
                        HStack(spacing: 8) {
                            chip("Top", c.minY, 0...max(0, key.bounds.height - 1)) { k, v in if var c = k.center { c.minY = min(v, c.maxY); k.center = c } }
                            chip("Bottom", key.bounds.height - 1 - c.maxY, 0...max(0, key.bounds.height - 1)) { k, v in
                                if var c = k.center { c.maxY = max(c.minY, k.bounds.height - 1 - v); k.center = c }
                            }
                        }
                    }
                }
                section("Pivot") {
                    PillToggle(title: "Pivot", isOn: Binding(get: { key.pivot != nil }, set: { on in
                        document.editActiveSlice { k in k.pivot = on ? PixelPoint(x: k.bounds.width / 2, y: k.bounds.height - 1) : nil }
                    }))
                    if let p = key.pivot {
                        HStack(spacing: 8) {
                            chip("X", p.x, -4096...4096) { k, v in k.pivot?.x = v }
                            chip("Y", p.y, -4096...4096) { k, v in k.pivot?.y = v }
                        }
                    }
                }
                Text("Changes on a later frame start a new key there, so a slice can move with the animation.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(Theme.panel)
        .onAppear { name = slice.name }
        .onDisappear { if name != slice.name { document.renameSlice(slice.id, to: name) } }
    }

    private var currentColor: PixelColor? { document.structure.slices.first { $0.id == slice.id }?.color }

    private func chip(_ title: LocalizedStringKey, _ value: Int, _ range: ClosedRange<Int>, set: @escaping (inout SliceKey, Int) -> Void) -> some View {
        NumberChip(title: title, value: Binding(get: { value }, set: { v in document.editActiveSlice { set(&$0, v) } }), range: range, unit: "px")
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted).textCase(.uppercase)
            content()
        }
    }
}
