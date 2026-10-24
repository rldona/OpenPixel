import SwiftUI

/// Aseprite's Hue/Saturation window: floats over the editor (at first over the
/// side panel) and can be dragged by its title; the canvas shows the result
/// while the sliders move. Apply makes it one undo step.
/// https://www.aseprite.org/docs/hue-saturation/
struct HueSaturationPanel: View {
    let document: SpriteDocument
    /// The space it can be dragged in.
    let area: CGSize
    @State private var adjustment = HueSaturation()
    @State private var everyCel = false
    /// Where it was dragged to, from its place at the top right; kept between uses.
    @AppStorage("hueSaturationOffsetX") private var offsetX = 0.0
    @AppStorage("hueSaturationOffsetY") private var offsetY = 0.0
    @GestureState private var drag = CGSize.zero
    private static let width: CGFloat = EditorView.panelWidth - 16
    private static let approximateHeight: CGFloat = 425

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                Text("Hue/Saturation").font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Button("Reset") { adjustment = HueSaturation(mode: adjustment.mode) }
                    .font(.system(size: 13, weight: .medium))
                    .disabled(adjustment.isIdentity)
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
            .gesture(dragGesture)
            // Double tap the title to put it back over the side panel.
            .onTapGesture(count: 2) { withAnimation(.snappy) { offsetX = 0; offsetY = 0 } }
            .accessibilityHint(Text("Drag to move the window"))

            Picker("Mode", selection: $adjustment.mode) {
                ForEach(HueSaturation.Mode.allCases) { Text(verbatim: $0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 10) {
                slider("H", value: $adjustment.hue, range: -180...180, unit: "°")
                slider("S", value: percent(\.saturation), range: -100...100, unit: "%")
                slider(adjustment.mode.usesLightness ? "L" : "V", value: percent(\.lightness), range: -100...100, unit: "%")
                slider("A", value: percent(\.alpha), range: -100...100, unit: "%")
            }

            HStack(spacing: 6) {
                channel("R", \.red)
                channel("G", \.green)
                channel("B", \.blue)
                channel("A", \.alphaChannel)
            }

            Picker("Where", selection: $everyCel) {
                Text("Current cel").tag(false)
                Text("Every cel").tag(true)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                Button { document.endHueSaturation(apply: nil, everyCel: everyCel) } label: {
                    Text("Cancel").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 10))
                .keyboardShortcut(.cancelAction)
                Button { document.endHueSaturation(apply: adjustment, everyCel: everyCel) } label: {
                    Text("Apply").fontWeight(.semibold).foregroundStyle(Theme.onAccent).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                .keyboardShortcut(.defaultAction)
            }
            .font(.system(size: 15))
        }
        .padding(14)
        .frame(width: Self.width)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .offset(clamped(CGSize(width: offsetX + drag.width, height: offsetY + drag.height)))
        // A short pause between slider moves keeps big sprites responsive.
        .task(id: Preview(adjustment: adjustment, everyCel: everyCel)) {
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            document.previewHueSaturation(adjustment, everyCel: everyCel)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .global)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                let end = clamped(CGSize(width: offsetX + value.translation.width, height: offsetY + value.translation.height))
                offsetX = end.width
                offsetY = end.height
            }
    }

    /// Keeps it inside the editor: it starts at the top right, so it can go left and down.
    private func clamped(_ offset: CGSize) -> CGSize {
        let maxLeft = max(0, area.width - Self.width - 16), maxDown = max(0, area.height - Self.approximateHeight)
        return CGSize(width: min(0, max(-maxLeft, offset.width)), height: min(maxDown, max(0, offset.height)))
    }

    private struct Preview: Hashable {
        var adjustment: HueSaturation
        var everyCel: Bool
    }

    /// The model keeps -1...1; the sliders show -100...100.
    private func percent(_ keyPath: WritableKeyPath<HueSaturation, Double>) -> Binding<Double> {
        Binding(get: { adjustment[keyPath: keyPath] * 100 }, set: { adjustment[keyPath: keyPath] = $0 / 100 })
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(width: 16)
            Slider(value: value, in: range, step: 1)
                .tint(Theme.accent)
            Text(verbatim: "\(Int(value.wrappedValue.rounded()))\(unit)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .frame(width: 52, alignment: .trailing)
                // Double tap goes back to zero.
                .onTapGesture(count: 2) { value.wrappedValue = 0 }
        }
    }

    private func channel(_ label: String, _ keyPath: WritableKeyPath<HueSaturation, Bool>) -> some View {
        let isOn = adjustment[keyPath: keyPath]
        return Button { adjustment[keyPath: keyPath].toggle() } label: {
            Text(verbatim: label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(isOn ? Theme.accent : Theme.muted)
                .frame(width: 34, height: 32)
                .background(isOn ? Theme.accentSoft : Theme.chip, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
