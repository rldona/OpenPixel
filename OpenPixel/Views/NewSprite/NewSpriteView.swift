import SwiftUI

struct NewSpriteView: View {
    enum Background: String, CaseIterable, Identifiable {
        case transparent, white, black
        var id: String { rawValue }

        var title: String {
            switch self {
            case .transparent: "Transparente"
            case .white: "Blanco"
            case .black: "Negro"
            }
        }

        var color: PixelColor? {
            switch self {
            case .transparent: nil
            case .white: .white
            case .black: .black
            }
        }
    }

    let onCreate: (String, Sprite) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Sin título"
    @State private var width = 32
    @State private var height = 32
    @State private var background = Background.transparent
    @State private var palette = Palette.pico8

    private let presets = [16, 32, 64, 128, 256]
    private let limit = 1024

    var body: some View {
        NavigationStack {
            ScrollView {
                HStack(alignment: .top, spacing: 28) {
                    VStack(alignment: .leading, spacing: 24) {
                        TextField("Nombre", text: $name)
                            .font(.title3.weight(.semibold))
                            .padding(12)
                            .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("Tamaño (píxeles)")
                            HStack(spacing: 8) {
                                ForEach(presets, id: \.self) { n in
                                    Chip(title: "\(n)", isOn: width == n && height == n) {
                                        width = n
                                        height = n
                                    }
                                }
                            }
                            DimensionField(title: "Ancho", value: $width, limit: limit)
                            DimensionField(title: "Alto", value: $height, limit: limit)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("Fondo")
                            Picker("Fondo", selection: $background) {
                                ForEach(Background.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel("Paleta inicial")
                            ForEach(Palette.all) { p in
                                Button { palette = p } label: {
                                    HStack(spacing: 12) {
                                        Text(p.name).frame(width: 140, alignment: .leading).lineLimit(1)
                                        HStack(spacing: 0) {
                                            ForEach(Array(p.colors.enumerated()), id: \.offset) { _, c in
                                                Rectangle().fill(c.color)
                                            }
                                        }
                                        .frame(height: 18)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    .padding(12)
                                    .background(palette == p ? Color(hex: 0x2A211E) : Theme.field, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette == p ? Theme.accent : Theme.border))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Vista previa")
                        preview
                            .frame(width: 180, height: 180)
                            .background(Theme.field, in: RoundedRectangle(cornerRadius: 16))
                        Text(verbatim: "\(width) × \(height) px · RGBA\n1 capa · 1 frame de 100 ms")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(width: 180)
                }
                .padding(28)
            }
            .background(Color(hex: 0x1A1A1F))
            .navigationTitle("Nuevo sprite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Crear") {
                        let sprite = Sprite.blank(width: width, height: height, background: background.color, palette: palette.colors)
                        dismiss()
                        onCreate(name.trimmingCharacters(in: .whitespaces).isEmpty ? "Sin título" : name, sprite)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var preview: some View {
        let side: CGFloat = 148
        let factor = side / CGFloat(max(width, height))
        return ZStack {
            switch background {
            case .transparent: Checkerboard(cell: 10)
            case .white: Color.white
            case .black: Color.black
            }
        }
        .frame(width: max(2, CGFloat(width) * factor), height: max(2, CGFloat(height) * factor))
        .overlay(Rectangle().strokeBorder(Color(hex: 0x3A3A43)))
    }
}

private struct Chip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium).monospacedDigit())
                .fixedSize()
                .frame(minWidth: 44, minHeight: 44)
                .foregroundStyle(isOn ? Color(hex: 0xFFB29E) : Theme.text)
                .background(isOn ? Color(hex: 0x2A211E) : Theme.field, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isOn ? Theme.accent : Theme.border))
        }
        .buttonStyle(.plain)
    }
}

private struct DimensionField: View {
    let title: String
    @Binding var value: Int
    let limit: Int

    var body: some View {
        HStack {
            Text(title).foregroundStyle(Theme.muted)
            TextField(title, value: $value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.body.weight(.semibold).monospacedDigit())
                .onChange(of: value) { _, new in value = min(limit, max(1, new)) }
            Stepper(title, value: $value, in: 1...limit).labelsHidden()
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 48)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
    }
}
