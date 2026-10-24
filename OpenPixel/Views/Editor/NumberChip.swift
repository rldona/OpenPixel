import SwiftUI

/// A number in the tool options bar. Small −/+ buttons are hard to hit on a
/// touch screen and change one step at a time, so the value is a chip that
/// opens a popover: common values, a slider, a field to type the number,
/// and large −/+ buttons.
struct NumberChip: View {
    let title: LocalizedStringKey
    var systemImage: String?
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var unit = ""
    var presets: [Int] = []
    /// A narrower span for the slider when the full range is too wide to drag precisely.
    var sliderRange: ClosedRange<Int>?
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.muted)
                } else {
                    Text(title).font(.system(size: 13, weight: .medium))
                }
                Text(verbatim: label(value))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.text)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(showing ? Theme.accentSoft : Theme.chip, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: label(value)))
        .accessibilityAdjustableAction { direction in
            set(value + (direction == .increment ? step : -step))
        }
        .popover(isPresented: $showing) {
            NumberPopover(title: title, value: $value, range: range, step: step, unit: unit, presets: presets, sliderRange: sliderRange ?? range)
                .presentationCompactAdaptation(.popover)
        }
    }

    private func label(_ v: Int) -> String { unit.isEmpty ? "\(v)" : unit == "°" ? "\(v)°" : "\(v) \(unit)" }
    private func set(_ v: Int) { value = min(range.upperBound, max(range.lowerBound, v)) }
}

private struct NumberPopover: View {
    let title: LocalizedStringKey
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String
    let presets: [Int]
    let sliderRange: ClosedRange<Int>
    @State private var text = ""
    @FocusState private var typing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted).textCase(.uppercase)

            HStack(spacing: 10) {
                bigButton("minus", label: "Less") { set(value - step) }
                    .disabled(value <= range.lowerBound)
                HStack(spacing: 4) {
                    TextField(text: $text) { Text(verbatim: "\(value)") }
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .focused($typing)
                        .onSubmit(commit)
                    if !unit.isEmpty {
                        Text(verbatim: unit).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(typing ? Theme.accent : Theme.border))
                bigButton("plus", label: "More") { set(value + step) }
                    .disabled(value >= range.upperBound)
            }

            Slider(value: Binding(get: { Double(min(sliderRange.upperBound, max(sliderRange.lowerBound, value))) },
                                  set: { set(max(sliderRange.lowerBound, Int(($0 / Double(step)).rounded()) * step)) }),
                   in: Double(sliderRange.lowerBound)...Double(sliderRange.upperBound))
                .tint(Theme.accent)

            if !presets.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: min(5, presets.count)), spacing: 8) {
                    ForEach(presets, id: \.self) { preset in
                        Button { set(preset) } label: {
                            Text(verbatim: "\(preset)")
                                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                                .foregroundStyle(value == preset ? Theme.onAccent : Theme.text)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(value == preset ? Theme.accent : Theme.chip, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .background(Theme.panel)
        .onAppear { text = "\(value)" }
        .onChange(of: value) { if !typing { text = "\(value)" } }
        // Tapping the field starts with it empty (the value stays as the
        // placeholder), so typing replaces the number instead of adding to it.
        .onChange(of: typing) { if typing { text = "" } else { commit() } }
    }

    private func bigButton(_ icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .frame(width: 52, height: 52)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
        .accessibilityLabel(Text(label))
    }

    private func commit() {
        if let typed = Int(text.filter(\.isNumber)) { set(typed) }
        text = "\(value)"
    }

    private func set(_ v: Int) {
        value = min(range.upperBound, max(range.lowerBound, v))
        if !typing { text = "\(value)" }
    }
}
