import SwiftUI
import UniformTypeIdentifiers

struct SidePanel: View {
    @Bindable var document: SpriteDocument
    let canvas: CanvasController
    /// On the left of the canvas, so its divider goes on the right.
    var mirrored = false
    @State private var editingPrimary = false
    @State private var editingSecondary = false
    /// Which color the square under the palette edits.
    @State private var pickingSecondary = false
    /// Palette edit mode: taps select a run of entries instead of picking a color.
    @State private var isEditingPalette = false
    @State private var paletteRange: ClosedRange<Int>?
    @State private var paletteAnchor: Int?
    @State private var editingEntry: PaletteEntry?
    @State private var importingPalette = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 8)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Preview")
                    // Updates when a stroke is committed, not on every stroke sample.
                    AnimatedPreview(document: document)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
                    viewButtons
                }

                paletteSection
                colorSection
                // Only while a tilemap layer is active.
                if let tileset = document.activeLayer?.tileset {
                    TilesetPanel(document: document, tileset: tileset)
                }
            }
            .padding(16)
        }
        // Background and divider run under the home indicator; the content stays in the safe area.
        .background {
            HStack(spacing: 0) {
                if !mirrored { Rectangle().fill(Theme.border).frame(width: 1) }
                Theme.panel
                if mirrored { Rectangle().fill(Theme.border).frame(width: 1) }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .sheet(item: $editingEntry) { entry in
            PaletteEntryEditor(color: entry.color, index: entry.index) { document.setPaletteColor($0, at: entry.index) }
        }
        .fileImporter(isPresented: $importingPalette, allowedContentTypes: [.data]) { result in
            importPalette(result)
        }
    }

    // MARK: View

    /// Aseprite's 100% / Center / Fit Screen buttons for the canvas.
    private var viewButtons: some View {
        HStack(spacing: 6) {
            viewButton(Text(verbatim: "100%"), label: "Actual size") { canvas.actualSize() }
                .keyboardShortcut("1", modifiers: .command)
            viewButton(Text("Center"), label: "Center") { canvas.center() }
            viewButton(Text("Fit screen"), label: "Fit to screen") { canvas.fit() }
        }
    }

    private func viewButton(_ title: Text, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            title
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Theme.chip, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    // MARK: Colors

    /// Aseprite's selector under the palette: the square edits whichever of
    /// the two colors is picked in the chips below it.
    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Color")
            QuickColorPicker(color: pickingSecondary ? $document.secondary : $document.primary)
            HStack(spacing: 6) {
                colorChip(secondary: false)
                colorChip(secondary: true)
            }
            // Swapping the colors, then what changes the sprite's own colors;
            // the bottom two open floating windows and stay lit while they're open.
            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    colorAction("Swap", "arrow.left.arrow.right") { document.swapColors() }
                    colorAction("Replace…", "drop.halffull") { document.isReplacingColor = true }
                        .accessibilityLabel(Text("Replace color…"))
                }
                GridRow {
                    // One window at a time: each opens its own and closes the other, or
                    // closes its own when it's open. Hue/Saturation closes without applying, like Cancel.
                    colorAction("Hue/Saturation", "slider.horizontal.3", isOn: document.isAdjustingHueSaturation) {
                        if document.isAdjustingHueSaturation {
                            document.endHueSaturation(apply: nil, everyCel: false)
                        } else {
                            document.beginHueSaturation()
                        }
                    }
                    colorAction("Color shading", "swatchpalette", isOn: document.isShowingColorShading) {
                        document.toggleColorShading()
                    }
                }
            }
        }
    }

    private func colorAction(_ title: LocalizedStringKey, _ systemImage: String, isOn: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.system(size: 16, weight: .medium)).frame(height: 20)
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(isOn ? Theme.accent : Theme.text)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(isOn ? Theme.accentSoft : Theme.chip, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// One of the two colors: its swatch, its hex (typed to change it) and,
    /// while it isn't in the palette, Aseprite's warning that adds it.
    /// Tapping picks it for the square; tapping the picked swatch opens the full editor.
    private func colorChip(secondary: Bool) -> some View {
        let color = secondary ? document.secondary : document.primary
        let isOn = pickingSecondary == secondary
        let binding = secondary ? $document.secondary : $document.primary
        return HStack(spacing: 6) {
            Button {
                if isOn { if secondary { editingSecondary = true } else { editingPrimary = true } } else { pickingSecondary = secondary }
            } label: {
                ZStack {
                    Checkerboard(cell: 5)
                    color.color
                }
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.strongBorder))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(secondary ? Text("Secondary color") : Text("Primary color"))
            .accessibilityValue(Text(verbatim: color.hex))
            .accessibilityHint(isOn ? Text("Opens the color editor") : Text("Edits it with the square"))
            // Aseprite's warning, as a badge: the color isn't in the palette; tapping adds it.
            .overlay(alignment: .topTrailing) {
                if document.paletteIndex(of: color) == nil {
                    Button { document.addToPalette(color) } label: {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Theme.onAccent)
                            .frame(width: 16, height: 16)
                            .background(Theme.accent, in: Circle())
                            .overlay(Circle().strokeBorder(Theme.panel, lineWidth: 1.5))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: 12, y: -12)
                    .accessibilityLabel(Text("Not in palette"))
                    .accessibilityHint(Text("Adds it to the palette"))
                }
            }
            .popover(isPresented: secondary ? $editingSecondary : $editingPrimary) {
                ColorEditor(color: binding, palette: document.structure.palette) { document.addToPalette($0) }
                    .presentationCompactAdaptation(.popover)
            }

            HexField(color: binding)
                .simultaneousGesture(TapGesture().onEnded { pickingSecondary = secondary })
        }
        .padding(5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isOn ? Theme.accentSoft : Theme.chip, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isOn ? Theme.accent : .clear, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { pickingSecondary = secondary }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Palette

    private var paletteSection: some View {
        let palette = document.structure.palette
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SectionLabel("Palette")
                Text(verbatim: "\(palette.count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button {
                    isEditingPalette.toggle()
                    paletteRange = nil
                    paletteAnchor = nil
                } label: {
                    Text(isEditingPalette ? "Done" : "Edit colors").font(.system(size: 13, weight: .semibold))
                }
                paletteMenu
            }
            // Big palettes scroll inside a few rows, so the colors below stay in view.
            // The cap cuts a row in half to show there's more.
            ViewThatFits(in: .vertical) {
                paletteGrid(palette)
                ScrollView { paletteGrid(palette) }
            }
            .frame(maxHeight: 200)
            if isEditingPalette { paletteEditBar }
        }
    }

    private func paletteGrid(_ palette: [PixelColor]) -> some View {
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(Array(palette.enumerated()), id: \.offset) { index, color in
                swatch(color, index: index)
            }
        }
    }

    private var paletteMenu: some View {
        Menu {
            Menu("Load preset") {
                ForEach(Palette.all) { preset in
                    Button(LocalizedStringKey(preset.name)) { document.setPalette(preset.colors) }
                }
                // Palettes from Aseprite extensions (Preferences > Extensions).
                let extensionPalettes = ExtensionStore.shared.palettes
                if !extensionPalettes.isEmpty {
                    Section("Extensions") {
                        ForEach(extensionPalettes) { palette in
                            Button(palette.id) { document.setPalette(palette.colors) }
                        }
                    }
                }
            }
            Button("Palette from sprite", systemImage: "eyedropper.halffull") { document.paletteFromSprite() }
            Divider()
            Button("Import palette…", systemImage: "square.and.arrow.down") { importingPalette = true }
            Menu("Export palette") {
                ForEach(PaletteFile.Format.allCases) { format in
                    ShareLink(item: PaletteExport(colors: document.structure.palette, name: document.name, format: format),
                              preview: SharePreview(Text(verbatim: "\(document.name).\(format.rawValue)"))) {
                        Text(verbatim: format.title)
                    }
                }
            }
            Divider()
            Button("Save as default palette", systemImage: "star") {
                Palette.saveDefault(document.structure.palette)
                document.notice = L10n.string("New sprites will start with this palette")
            }
            if Palette.savedDefault != nil {
                Button("Forget default palette", systemImage: "star.slash") { Palette.clearSavedDefault() }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 32, height: 32)
                .foregroundStyle(Theme.text)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("Palette options"))
    }

    private func swatch(_ color: PixelColor, index: Int) -> some View {
        let selected = isEditingPalette && (paletteRange?.contains(index) ?? false)
        let isPrimary = color == document.primary, isSecondary = color == document.secondary
        let tile = Button {
            if isEditingPalette { extendPaletteSelection(to: index) } else { pick(color) }
        } label: {
            ZStack {
                Checkerboard(cell: 4)
                color.color
            }
            .frame(height: 26)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                selected ? Theme.accent : (isPrimary && !isEditingPalette ? Theme.text : .white.opacity(0.08)),
                lineWidth: selected ? 2.5 : (isPrimary && !isEditingPalette ? 2 : 1)
            ))
            // Corner marks for the primary and secondary colors, as in Aseprite's color bar.
            .overlay(alignment: .topLeading) { if isPrimary { CornerMark().fill(Theme.text).frame(width: 9, height: 9).padding(2) } }
            .overlay(alignment: .bottomTrailing) { if isSecondary { CornerMark().rotation(.degrees(180)).fill(Theme.text).frame(width: 9, height: 9).padding(2) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Color \(color.hex)"))
        .accessibilityValue(selected ? Text("Selected") : Text(verbatim: ""))
        .contextMenu {
            Button("Use as primary", systemImage: "paintbrush.pointed") { pick(color) }
            Button("Use as secondary", systemImage: "square.2.layers.3d.bottom.filled") { document.secondary = color }
            Button("Edit color…", systemImage: "slider.horizontal.3") { editingEntry = PaletteEntry(index: index, color: color) }
            Divider()
            Button("Remove from palette", systemImage: "trash", role: .destructive) { document.removeFromPalette(at: index) }
                .disabled(document.structure.palette.count <= 1)
        }
        return Group {
            if isEditingPalette {
                // Drag to reorder: a selected run moves together.
                tile
                    .draggable("palette:\(index)") {
                        RoundedRectangle(cornerRadius: 6).fill(color.color).frame(width: 30, height: 30)
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let source = items.first.flatMap(Self.paletteIndex) else { return false }
                        let run = paletteRange.flatMap { $0.contains(source) ? $0 : nil } ?? source...source
                        let placed = document.movePaletteColors(run, to: index)
                        paletteRange = placed
                        paletteAnchor = placed.lowerBound
                        return true
                    }
            } else {
                tile
            }
        }
    }

    private static func paletteIndex(_ payload: String) -> Int? {
        guard payload.hasPrefix("palette:") else { return nil }
        return Int(payload.dropFirst(8))
    }

    private func pick(_ color: PixelColor) {
        document.primary = color
        if document.tool == .eraser || document.tool == .eyedropper { document.select(.pencil) }
    }

    /// First tap anchors, the next ones extend the run; tapping a lone selected entry clears it.
    private func extendPaletteSelection(to index: Int) {
        if let anchor = paletteAnchor, paletteRange != nil {
            if paletteRange == index...index {
                paletteRange = nil
                paletteAnchor = nil
            } else {
                paletteRange = min(anchor, index)...max(anchor, index)
            }
        } else {
            paletteAnchor = index
            paletteRange = index...index
        }
    }

    /// Actions on the selected entries (Aseprite's Sort & Gradients).
    private var paletteEditBar: some View {
        let range = paletteRange
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                editButton("Edit color…", "slider.horizontal.3", enabled: range != nil) {
                    if let i = range?.lowerBound { editingEntry = PaletteEntry(index: i, color: document.structure.palette[i]) }
                }
                editButton("Gradient", "square.split.diagonal.2x2", enabled: (range?.count ?? 0) > 2) {
                    if let range { document.paletteGradient(range) }
                }
                editButton("Reverse", "arrow.left.arrow.right", enabled: (range?.count ?? 0) > 1) {
                    if let range { document.reversePalette(range) }
                }
                Menu {
                    ForEach(PaletteSort.allCases) { order in
                        Button(order.title) { document.sortPalette(sortRange, by: order) }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 38, height: 34)
                        .foregroundStyle(Theme.text)
                }
                .accessibilityLabel(Text("Sort"))
                editButton("Duplicate", "plus.square.on.square", enabled: range != nil) {
                    if let range { document.duplicatePaletteColors(range) }
                }
                editButton("Delete", "trash", enabled: range != nil) {
                    if let range {
                        document.removePaletteColors(range)
                        paletteRange = nil
                        paletteAnchor = nil
                    }
                }
            }
        }
    }

    /// Sorting applies to the selection, or to the whole palette when nothing is selected.
    private var sortRange: ClosedRange<Int> {
        paletteRange.flatMap { $0.count > 1 ? $0 : nil } ?? 0...max(0, document.structure.palette.count - 1)
    }

    private func editButton(_ title: LocalizedStringKey, _ systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 38, height: 34)
                .foregroundStyle(Theme.text)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
        .accessibilityLabel(Text(title))
    }

    private func importPalette(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let colors = PaletteFile.colors(from: data, fileExtension: url.pathExtension) else {
            document.notice = L10n.string("Couldn't read a palette from that file")
            return
        }
        document.setPalette(colors)
    }
}

extension PaletteSort {
    var title: LocalizedStringKey {
        switch self {
        case .hue: "By hue"
        case .saturation: "By saturation"
        case .brightness: "By brightness"
        case .luminance: "By luminance"
        }
    }
}

private struct PaletteEntry: Identifiable {
    let index: Int
    let color: PixelColor
    var id: Int { index }
}

/// Edits one palette entry; the change is one undo step, applied on Save.
private struct PaletteEntryEditor: View {
    @State var color: PixelColor
    let index: Int
    let onSave: (PixelColor) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView { ColorEditor(color: $color) }
                .navigationTitle(Text("Palette color \(index)"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave(color)
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.large])
    }
}

/// A small right triangle in the top-left corner.
private struct CornerMark: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: rect.origin)
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

/// A palette file for the share sheet (Save to Files, AirDrop…).
struct PaletteExport: Transferable {
    let colors: [PixelColor]
    let name: String
    let format: PaletteFile.Format

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .data) { item in
            let safeName = item.name.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).\(item.format.rawValue)")
            try PaletteFile.data(item.colors, name: item.name, format: item.format).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// A color's hex, typed and applied on return; it follows the color otherwise.
private struct HexField: View {
    @Binding var color: PixelColor
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Hex", text: $text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .focused($focused)
            .lineLimit(1)
            .onSubmit {
                if let parsed = PixelColor(hex: text) { color = parsed } else { text = color.hex }
            }
            .onAppear { text = color.hex }
            // Typing only changes the color on return, so any change comes from elsewhere.
            .onChange(of: color) { _, new in text = new.hex }
            .onChange(of: focused) { _, isFocused in if !isFocused { text = color.hex } }
    }
}
