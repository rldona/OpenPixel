import SwiftUI

/// Aseprite's Hue/Saturation window: the canvas shows the result while the
/// sliders move. Apply makes it one undo step.
/// https://www.aseprite.org/docs/hue-saturation/
struct HueSaturationPanel: View {
    let document: SpriteDocument
    /// The space it can be dragged in.
    let area: CGSize
    /// How far its starting place is from the area's right edge.
    let trailingInset: CGFloat
    @State private var adjustment = HueSaturation()
    @State private var everyCel = false

    var body: some View {
        FloatingWindow("Hue/Saturation", id: "hueSaturation", area: area, trailingInset: trailingInset, approximateHeight: 425) {
            Button("Reset") { adjustment = HueSaturation(mode: adjustment.mode) }
                .font(.system(size: 13, weight: .medium))
                .disabled(adjustment.isIdentity)
        } content: {
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
        // A short pause between slider moves keeps big sprites responsive.
        .task(id: Preview(adjustment: adjustment, everyCel: everyCel)) {
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            document.previewHueSaturation(adjustment, everyCel: everyCel)
        }
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
