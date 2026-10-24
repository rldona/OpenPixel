import SwiftUI

/// Typing the text after tapping the canvas with the text tool, with a live
/// preview in the actual pixels. Placing it leaves floating pixels to move
/// or scale before applying (Aseprite's Edit > Insert Text).
struct TextEntrySheet: View {
    @Bindable var document: SpriteDocument
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Text", text: $text, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($focused)
                    preview
                        .frame(height: 140)
                        .listRowInsets(EdgeInsets())
                }
                Section("Font") {
                    TextFontPicker(style: $document.textStyle)
                    TextSizeStepper(style: $document.textStyle)
                    Stepper(value: $document.textStyle.letterSpacing, in: 0...8) {
                        LabeledContent("Letter spacing") { Text(verbatim: "\(document.textStyle.letterSpacing) px") }
                    }
                    Stepper(value: $document.textStyle.lineSpacing, in: 0...16) {
                        LabeledContent("Line spacing") { Text(verbatim: "\(document.textStyle.lineSpacing) px") }
                    }
                    Picker("Alignment", selection: $document.textStyle.alignment) {
                        ForEach(TextStyle.Alignment.allCases) { Image(systemName: $0.systemImage).tag($0).accessibilityLabel($0.title) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Outline in the secondary color", isOn: $document.textStyle.outline)
                }
            }
            .navigationTitle("Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        document.textAnchor = nil
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Place") {
                        if !document.placeText(text) { document.notice = L10n.string("The text has no visible pixels") }
                        dismiss()
                    }
                    .disabled(rendered == nil)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.large])
    }

    private var rendered: PixelImage? {
        var outline = document.secondary
        outline.a = 255
        return TextRenderer.render(text, style: document.textStyle, color: document.primary, outlineColor: outline)
    }

    private var preview: some View {
        ZStack {
            if let image = rendered {
                PixelThumbnail(image: image.makeCGImage())
                Text(verbatim: "\(image.width) × \(image.height) px")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            } else {
                Checkerboard()
                Text("Type to see the text in pixels").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// Pixel fonts first (they're what pixel art wants), then system fonts
/// drawn without antialiasing.
struct TextFontPicker: View {
    @Binding var style: TextStyle

    var body: some View {
        Picker("Font", selection: $style.font) {
            Section("Pixel fonts") {
                ForEach(PixelFont.all) { Text(verbatim: $0.name).tag(TextStyle.Font.pixel($0.id)) }
            }
            Section("System fonts, no smoothing") {
                Text("System").tag(TextStyle.Font.system(""))
                ForEach(TextStyle.systemFamilies, id: \.self) { Text(verbatim: $0).tag(TextStyle.Font.system($0)) }
            }
        }
        .pickerStyle(.menu)
    }
}

/// Whole-pixel scale for pixel fonts, size in pixels for system fonts.
struct TextSizeStepper: View {
    @Binding var style: TextStyle

    var body: some View {
        if case .pixel = style.font {
            Stepper(value: $style.scale, in: 1...8) {
                LabeledContent("Scale") { Text(verbatim: "×\(style.scale)") }
            }
        } else {
            Stepper(value: $style.pointSize, in: 6...128, step: 2) {
                LabeledContent("Size") { Text(verbatim: "\(style.pointSize) px") }
            }
        }
    }
}

extension TextStyle.Alignment {
    var systemImage: String {
        switch self {
        case .left: "text.alignleft"
        case .center: "text.aligncenter"
        case .right: "text.alignright"
        }
    }

    var title: Text {
        switch self {
        case .left: Text("Align left")
        case .center: Text("Center")
        case .right: Text("Align right")
        }
    }
}

extension TextStyle {
    /// Short name for the options bar.
    var fontName: String {
        switch font {
        case .pixel(let id): PixelFont.named(id)?.name ?? PixelFont.standard.name
        case .system(let family): family.isEmpty ? L10n.string("System") : family
        }
    }

    var sizeLabel: String {
        if case .pixel = font { return "×\(scale)" }
        return "\(pointSize) px"
    }
}
