import SwiftUI

/// The ink, opacity and Pencil dynamics, behind one button in the tool options bar.
struct InkButton: View {
    @Bindable var document: SpriteDocument
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 6) {
                Image(systemName: usesInk ? document.ink.systemImage : "circle.lefthalf.filled")
                    .font(.system(size: 14, weight: .medium))
                if usesInk { Text(document.ink.title) }
                Text(verbatim: "\(Int((Double(document.toolOpacity) / 255 * 100).rounded()))%")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                if hasDynamics, document.pressureSize || document.pressureOpacity {
                    Image(systemName: "applepencil.tip").foregroundStyle(Theme.accent)
                }
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.text)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Theme.chip, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Ink and opacity"))
        .popover(isPresented: $showing) {
            InkOptions(document: document, usesInk: usesInk, hasDynamics: hasDynamics)
                .presentationCompactAdaptation(.popover)
        }
    }

    /// The eraser always erases; it only has an opacity.
    private var usesInk: Bool { document.tool != .eraser }
    private var hasDynamics: Bool { document.tool == .pencil || document.tool == .eraser }
}

struct InkOptions: View {
    @Bindable var document: SpriteDocument
    let usesInk: Bool
    let hasDynamics: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if usesInk {
                section("Ink") {
                    VStack(spacing: 2) {
                        ForEach(Ink.allCases) { ink in
                            Button { document.ink = ink } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: ink.systemImage).frame(width: 22)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(ink.title).font(.system(size: 14, weight: .medium))
                                        Text(summary(of: ink)).font(.system(size: 12)).foregroundStyle(Theme.muted)
                                    }
                                    Spacer(minLength: 8)
                                    if document.ink == ink { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                                }
                                .foregroundStyle(Theme.text)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 44)
                                .background(document.ink == ink ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(document.ink == ink ? .isSelected : [])
                        }
                    }
                }
                if document.ink == .shading {
                    section("Shading direction") {
                        Picker("Shading direction", selection: $document.shadeDirection) {
                            Label("Previous palette color", systemImage: "arrow.left").tag(ShadeDirection.backward)
                            Label("Next palette color", systemImage: "arrow.right").tag(ShadeDirection.forward)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
            }
            section("Opacity") {
                HStack(spacing: 10) {
                    Slider(value: opacity, in: 1...255)
                    Text(verbatim: "\(Int((Double(document.toolOpacity) / 255 * 100).rounded()))%")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .frame(width: 44, alignment: .trailing)
                }
            }
            if hasDynamics {
                section("Apple Pencil pressure") {
                    VStack(spacing: 0) {
                        Toggle("Changes the size", isOn: $document.pressureSize).frame(minHeight: 44)
                        Toggle("Changes the opacity", isOn: $document.pressureOpacity).frame(minHeight: 44)
                    }
                    .font(.system(size: 14))
                    .tint(Theme.accent)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(Theme.panel)
    }

    private var opacity: Binding<Double> {
        Binding(get: { Double(document.toolOpacity) }, set: { document.toolOpacity = Int($0.rounded()) })
    }

    private func summary(of ink: Ink) -> LocalizedStringKey {
        switch ink {
        case .simple: "Paints the color; transparent erases"
        case .alphaCompositing: "Blends over what's there"
        case .copyColor: "Replaces color and transparency"
        case .lockAlpha: "Paints only over drawn pixels"
        case .shading: "Steps drawn pixels along the palette"
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted).textCase(.uppercase)
            content()
        }
    }
}
