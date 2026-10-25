import SwiftUI

/// Aseprite-style color selector: a spectrum, RGB and HSB sliders, hex and
/// alpha, plus shades and harmonies of the current color.
/// https://www.aseprite.org/docs/color-bar/#foreground-color
struct ColorEditor: View {
    @Binding var color: PixelColor
    var palette: [PixelColor] = []
    /// Shows "Add to palette" while the color isn't in the palette.
    var onAddToPalette: ((PixelColor) -> Void)?

    enum Mode: String, CaseIterable, Identifiable {
        case spectrum, rgb, hsb
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .spectrum: "Spectrum"
            case .rgb: "RGB"
            case .hsb: "HSB"
            }
        }
    }

    @AppStorage("colorEditorMode") private var mode = Mode.spectrum
    @AppStorage("colorEditorHarmony") private var harmony = ColorHarmony.complementary
    @AppStorage(EditorSettings.alphaFormatKey) private var alphaFormat = AlphaFormat.percent
    /// Kept apart from `color` so hue survives grays and black.
    @State private var hsv: HSV
    @State private var hexText: String
    /// The color when the editor opened; kept in state because the parent rebuilds this view as the color changes.
    @State private var original: PixelColor

    init(color: Binding<PixelColor>, palette: [PixelColor] = [], onAddToPalette: ((PixelColor) -> Void)? = nil) {
        _color = color
        self.palette = palette
        self.onAddToPalette = onAddToPalette
        _original = State(initialValue: color.wrappedValue)
        _hsv = State(initialValue: color.wrappedValue.hsv)
        _hexText = State(initialValue: color.wrappedValue.hex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            switch mode {
            case .spectrum:
                SaturationValueSquare(hsv: hsv) { setHSV($0) }
                    .frame(height: 170)
                HueBar(hue: hsv.h) { setHSV(HSV(h: $0, s: hsv.s, v: hsv.v)) }
                    .frame(height: 26)
            case .rgb:
                channel("R", value: Double(color.r), range: 0...255) { set(r: $0) }
                channel("G", value: Double(color.g), range: 0...255) { set(g: $0) }
                channel("B", value: Double(color.b), range: 0...255) { set(b: $0) }
            case .hsb:
                channel("H", value: hsv.h, range: 0...359) { setHSV(HSV(h: $0, s: hsv.s, v: hsv.v)) }
                channel("S", value: hsv.s * 100, range: 0...100) { setHSV(HSV(h: hsv.h, s: $0 / 100, v: hsv.v)) }
                channel("B", value: hsv.v * 100, range: 0...100) { setHSV(HSV(h: hsv.h, s: hsv.s, v: $0 / 100)) }
            }
            HStack(spacing: 10) {
                AlphaBar(color: color, format: alphaFormat) { set(a: $0) }
                    .frame(height: 26)
                Text(verbatim: alphaFormat.text(Double(color.a) / 255))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 48, alignment: .trailing)
            }

            swatchRow(title: "Shades", colors: color.shadesAndTints)
            VStack(alignment: .leading, spacing: 6) {
                Menu {
                    Picker("Harmony", selection: $harmony) {
                        ForEach(ColorHarmony.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(harmony.title)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                }
                .accessibilityLabel(Text("Harmony"))
                swatches(harmony.colors(for: color))
            }
        }
        .padding(16)
        .frame(width: 330)
        .onChange(of: color) { _, new in
            // Changes from outside (or from RGB and hex) move the HSB handles too.
            if PixelColor(hsv: hsv, alpha: new.a) != new { syncHSV(with: new) }
            if PixelColor(hex: hexText) != new { hexText = new.hex }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            // Before and after, like Aseprite's color popup.
            HStack(spacing: 0) {
                Button { color = original } label: { swatchFill(original) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Original color \(original.hex)"))
                swatchFill(color)
            }
            .frame(width: 64, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))

            TextField("Hex", text: $hexText)
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .onSubmit {
                    if let parsed = PixelColor(hex: hexText) { set(parsed) } else { hexText = color.hex }
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 8))

            if let onAddToPalette {
                if let index = palette.firstIndex(of: color) {
                    Text("#\(index)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                        .accessibilityLabel(Text("Palette index \(index)"))
                } else {
                    // Aseprite's warning: the color isn't in the palette yet.
                    Button { onAddToPalette(color) } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.accent)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Add to palette"))
                }
            }
        }
    }

    private func swatchFill(_ c: PixelColor) -> some View {
        ZStack {
            Checkerboard(cell: 5)
            c.color
        }
    }

    private func channel(_ label: String, value: Double, range: ClosedRange<Double>, set: @escaping (Double) -> Void) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .frame(width: 16)
            Slider(value: Binding(get: { value }, set: { set($0.rounded()) }), in: range)
            Text(verbatim: "\(Int(value.rounded()))")
                .font(.system(size: 13, design: .monospaced))
                .frame(width: 36, alignment: .trailing)
        }
    }

    private func swatchRow(title: LocalizedStringKey, colors: [PixelColor]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.muted)
            swatches(colors)
        }
    }

    private func swatches(_ colors: [PixelColor]) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                Button { set(c) } label: {
                    swatchFill(c)
                        .frame(height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(c == color ? Theme.text : Theme.border, lineWidth: c == color ? 2 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Color \(c.hex)"))
            }
        }
    }

    // MARK: Updates

    private func setHSV(_ new: HSV) {
        hsv = HSV(h: min(359.99, max(0, new.h)), s: min(1, max(0, new.s)), v: min(1, max(0, new.v)))
        color = PixelColor(hsv: hsv, alpha: color.a)
        hexText = color.hex
    }

    private func set(_ new: PixelColor) {
        syncHSV(with: new)
        color = new
        hexText = new.hex
    }

    private func set(r: Double? = nil, g: Double? = nil, b: Double? = nil, a: Double? = nil) {
        var c = color
        if let r { c.r = UInt8(r) }
        if let g { c.g = UInt8(g) }
        if let b { c.b = UInt8(b) }
        if let a { c.a = UInt8(min(255, max(0, a))) }
        if a != nil { color = c; hexText = c.hex } else { set(c) }
    }

    /// Takes the new color's HSV, keeping hue (and saturation) where they're undefined.
    private func syncHSV(with new: PixelColor) {
        var next = new.hsv
        if next.s == 0 || next.v == 0 { next.h = hsv.h }
        if next.v == 0 { next.s = hsv.s }
        hsv = next
    }
}

extension ColorHarmony {
    var title: LocalizedStringKey {
        switch self {
        case .complementary: "Complementary"
        case .analogous: "Analogous"
        case .triadic: "Triadic"
        case .splitComplementary: "Split complementary"
        case .tetradic: "Tetradic"
        }
    }
}

/// The side panel's always-on selector, as under Aseprite's palette: the
/// saturation and brightness square, then hue and opacity bars.
struct QuickColorPicker: View {
    @Binding var color: PixelColor
    @AppStorage(EditorSettings.alphaFormatKey) private var alphaFormat = AlphaFormat.percent
    /// Kept apart from `color` so hue survives grays and black.
    @State private var hsv: HSV

    init(color: Binding<PixelColor>) {
        _color = color
        _hsv = State(initialValue: color.wrappedValue.hsv)
    }

    var body: some View {
        VStack(spacing: 8) {
            SaturationValueSquare(hsv: hsv) { set($0) }
                .aspectRatio(1.75, contentMode: .fit)
            HueBar(hue: hsv.h, handleHeight: 24) { set(HSV(h: $0, s: hsv.s, v: hsv.v)) }
                .frame(height: 18)
            AlphaBar(color: color, format: alphaFormat, handleHeight: 24) { a in
                var c = color
                c.a = UInt8(min(255, max(0, a)))
                color = c
            }
            .frame(height: 18)
        }
        .onChange(of: color) { _, new in
            // A palette pick, the eyedropper or the other chip: the handles follow.
            guard PixelColor(hsv: hsv, alpha: new.a) != new else { return }
            var next = new.hsv
            if next.s == 0 || next.v == 0 { next.h = hsv.h }
            if next.v == 0 { next.s = hsv.s }
            hsv = next
        }
    }

    private func set(_ new: HSV) {
        hsv = HSV(h: min(359.99, max(0, new.h)), s: min(1, max(0, new.s)), v: min(1, max(0, new.v)))
        color = PixelColor(hsv: hsv, alpha: color.a)
    }
}

// MARK: - Controls

/// Saturation left to right, brightness bottom to top, for one hue.
private struct SaturationValueSquare: View {
    let hsv: HSV
    let onChange: (HSV) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ZStack {
                    PixelColor(hsv: HSV(h: hsv.h, s: 1, v: 1)).color
                    LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                // Outside the clip so it stays whole at the edges.
                Circle()
                    .strokeBorder(.white, lineWidth: 2.5)
                    .background(Circle().strokeBorder(.black.opacity(0.4), lineWidth: 4))
                    .frame(width: 20, height: 20)
                    .position(x: hsv.s * geo.size.width, y: (1 - hsv.v) * geo.size.height)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let s = drag.location.x / max(1, geo.size.width), v = 1 - drag.location.y / max(1, geo.size.height)
                onChange(HSV(h: hsv.h, s: min(1, max(0, s)), v: min(1, max(0, v))))
            })
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Saturation and brightness"))
        .accessibilityValue(Text(verbatim: "\(Int(hsv.s * 100)) %, \(Int(hsv.v * 100)) %"))
    }
}

private struct HueBar: View {
    let hue: Double
    var handleHeight: CGFloat = 32
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: stride(from: 0.0, through: 360, by: 60).map { PixelColor(hsv: HSV(h: $0 == 360 ? 359.99 : $0, s: 1, v: 1)).color },
                    startPoint: .leading, endPoint: .trailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Handle(height: handleHeight).position(x: hue / 360 * geo.size.width, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                onChange(min(359.99, max(0, drag.location.x / max(1, geo.size.width) * 360)))
            })
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Hue"))
        .accessibilityValue(Text(verbatim: "\(Int(hue))°"))
        .accessibilityAdjustableAction { direction in
            onChange(min(359.99, max(0, hue + (direction == .increment ? 10 : -10))))
        }
    }
}

private struct AlphaBar: View {
    let color: PixelColor
    let format: AlphaFormat
    var handleHeight: CGFloat = 32
    let onChange: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                ZStack {
                    Checkerboard(cell: 6)
                    LinearGradient(colors: [color.color.opacity(0), PixelColor(r: color.r, g: color.g, b: color.b).color], startPoint: .leading, endPoint: .trailing)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                Handle(height: handleHeight).position(x: Double(color.a) / 255 * geo.size.width, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                onChange((drag.location.x / max(1, geo.size.width) * 255).rounded())
            })
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Opacity"))
        .accessibilityValue(Text(verbatim: format.text(Double(color.a) / 255)))
        .accessibilityAdjustableAction { direction in
            onChange(Double(color.a) + (direction == .increment ? 16 : -16))
        }
    }
}

private struct Handle: View {
    var height: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.white)
            .frame(width: 8, height: height)
            .shadow(color: .black.opacity(0.35), radius: 2)
    }
}
