import SwiftUI
import UniformTypeIdentifiers

struct SidePanel: View {
    @Bindable var document: SpriteDocument
    let canvas: CanvasController
    /// On the left of the canvas, so its divider goes on the right.
    var mirrored = false
    /// Which color the square under the palette edits.
    @State private var pickingSecondary = false
    /// Palette edit mode: taps select a run of entries instead of picking a color.
    @State private var isEditingPalette = false
    @State private var paletteRange: ClosedRange<Int>?
    @State private var paletteAnchor: Int?
    @State private var editingEntry: PaletteEntry?
    @State private var savingPalette = false
    @State private var paletteName = ""
    /// The Tileset tab is on (only while a tilemap layer is active).
    @State private var showingTileset = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 10)

    var body: some View {
        // Everything fits without scrolling.
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    // Updates when a stroke is committed, not on every stroke sample.
                    AnimatedPreview(document: document)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
                    colorActions
                }

                // A tilemap layer's tileset shares the palette's place, as a tab,
                // so the panel doesn't grow.
                if let tileset = document.activeLayer?.tileset {
                    Picker("Show", selection: $showingTileset) {
                        Text("Palette").tag(false)
                        Text("Tileset").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    // The tabs take the room of a palette row or so, so the panel still fits.
                    if showingTileset {
                        ScrollView { TilesetPanel(document: document, tileset: tileset) }
                            .frame(height: 140)
                    } else {
                        paletteSection(maxHeight: 120)
                    }
                } else {
                    paletteSection()
                }
                colorSection
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Picking a tilemap layer shows its tiles; leaving it shows the palette.
        .onChange(of: document.activeLayer?.tileset != nil, initial: true) { _, isTilemap in showingTileset = isTilemap }
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
        .alert("Save palette", isPresented: $savingPalette) {
            TextField("Name", text: $paletteName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = paletteName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                Palette.save(document.structure.palette, name: name)
                document.notice = L10n.string("“%@” is now in Load preset", name)
            }
        } message: {
            Text("It shows up in Load preset for every sprite. A saved palette with the same name is replaced.")
        }
    }

    // MARK: Colors

    /// Aseprite's selector under the palette: the square edits whichever of
    /// the two colors is picked in the chips below it.
    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            QuickColorPicker(color: pickingSecondary ? $document.secondary : $document.primary)
            // Swap sits between the two colors, as in Aseprite's color bar.
            HStack(spacing: 4) {
                colorChip(secondary: false)
                Button { document.swapColors() } label: {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 24, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Swap colors"))
                colorChip(secondary: true)
            }
        }
    }

    /// Color shading, Hue/Saturation and Replace color: three floating windows
    /// that take turns. Under the preview.
    private var colorActions: some View {
        // Each button lights up while its window is open and closes it when tapped
        // again. Hue/Saturation closes without applying, like Cancel.
        HStack(spacing: 6) {
            colorAction("Color shading", "swatchpalette", isOn: document.isShowingColorShading) {
                document.toggleColorShading()
            }
            colorAction("Hue/Saturation", "slider.horizontal.3", isOn: document.isAdjustingHueSaturation) {
                if document.isAdjustingHueSaturation {
                    document.endHueSaturation(apply: nil, everyCel: false)
                } else {
                    document.beginHueSaturation()
                }
            }
            colorAction("Replace color…", "drop.halffull", isOn: document.isReplacingColor) {
                document.isReplacingColor.toggle()
            }
        }
    }

    /// The last colors painted with, newest first; tapping one picks it for
    /// the color the square edits. Empty slots keep the row's place.
    private var recentColors: some View {
        let colors = document.recentColors
        return HStack(spacing: 4) {
            ForEach(0..<SpriteDocument.recentColorCount, id: \.self) { i in
                if i < colors.count {
                    let color = colors[i]
                    Button {
                        if pickingSecondary { document.secondary = color } else { pick(color) }
                    } label: {
                        ZStack {
                            Checkerboard(cell: 3)
                            color.color
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Recent color \(color.hex)"))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .frame(maxWidth: .infinity)
                        .frame(height: 16)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    /// An icon button for a color action, with its name as the label.
    private func colorAction(_ title: LocalizedStringKey, _ systemImage: String, isOn: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(isOn ? Theme.accent : Theme.text)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(isOn ? Theme.accentSoft : Theme.chip, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(Text(title))
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// One of the two colors: its swatch, its hex and, for the primary while it
    /// isn't in the palette, Aseprite's warning that adds it. Tapping picks it for the square.
    private func colorChip(secondary: Bool) -> some View {
        let color = secondary ? document.secondary : document.primary
        let isOn = pickingSecondary == secondary
        return HStack(spacing: 6) {
            Button {
                pickingSecondary = secondary
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
            .accessibilityHint(Text("Edits it with the square"))
            // Aseprite's warning, as a badge: the color you paint with isn't in the
            // palette; tapping adds it. Only on the primary, the one that paints.
            .overlay(alignment: .topTrailing) {
                if !secondary && document.paletteIndex(of: color) == nil {
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

            // Read-only: the colors change with the square, the palette and the swap.
            Text(verbatim: color.hex)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
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

    private func paletteSection(maxHeight: CGFloat = 246) -> some View {
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
            // The last colors painted with, at hand right over the palette.
            recentColors
            // Up to 100 colors (ten rows of 21 pt swatches) fit; bigger palettes scroll
            // inside, so the colors below stay in view.
            ViewThatFits(in: .vertical) {
                paletteGrid(palette)
                ScrollView { paletteGrid(palette) }
            }
            .frame(maxHeight: maxHeight)
            if isEditingPalette { paletteEditBar }
        }
    }

    private func paletteGrid(_ palette: [PixelColor]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(palette.enumerated()), id: \.offset) { index, color in
                    swatch(color, index: index)
                }
                if !isEditingPalette && palette.count < PaletteFile.maxColors { addSwatch }
            }
            if palette.isEmpty {
                Text("Pick a color and tap + to add it to the palette.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The last tile: adds the primary color, to build a palette by hand.
    private var addSwatch: some View {
        let inPalette = document.paletteIndex(of: document.primary) != nil
        return Button { document.addToPalette(document.primary) } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(inPalette ? Theme.muted.opacity(0.5) : Theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 21)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(inPalette)
        .accessibilityLabel(Text("Add the primary color to the palette"))
    }

    private var paletteMenu: some View {
        Menu {
            Menu("Load preset") {
                let saved = Palette.saved
                if !saved.isEmpty {
                    Section("My palettes") {
                        ForEach(saved) { palette in
                            Button(palette.name) { document.setPalette(palette.colors) }
                        }
                    }
                }
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
            Button("New empty palette", systemImage: "square.dashed") { document.clearPalette() }
            Divider()
            Button("Import palette…", systemImage: "square.and.arrow.down") { document.fileImport = .palette }
            Menu("Export palette") {
                ForEach(PaletteFile.Format.allCases) { format in
                    ShareLink(item: PaletteExport(colors: document.structure.palette, name: document.name, format: format),
                              preview: SharePreview(Text(verbatim: "\(document.name).\(format.rawValue)"))) {
                        Text(verbatim: format.title)
                    }
                }
            }
            Divider()
            Button("Save palette as…", systemImage: "square.and.arrow.down.on.square") {
                paletteName = document.name
                savingPalette = true
            }
            .disabled(document.structure.palette.isEmpty)
            let saved = Palette.saved
            if !saved.isEmpty {
                Menu("Delete saved palette", systemImage: "trash") {
                    ForEach(saved) { palette in
                        Button(palette.name, role: .destructive) {
                            Palette.deleteSaved(named: palette.name)
                            document.notice = L10n.string("Deleted “%@”", palette.name)
                        }
                    }
                }
            }
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
            .frame(height: 21)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(
                selected ? Theme.accent : (isPrimary && !isEditingPalette ? Theme.text : Theme.border),
                lineWidth: selected ? 2.5 : (isPrimary && !isEditingPalette ? 2 : 1)
            ))
            // Corner marks for the primary and secondary colors, as in Aseprite's color bar.
            .overlay(alignment: .topLeading) { if isPrimary { CornerMark().fill(Theme.text).frame(width: 7, height: 7).padding(2) } }
            .overlay(alignment: .bottomTrailing) { if isSecondary { CornerMark().rotation(.degrees(180)).fill(Theme.text).frame(width: 7, height: 7).padding(2) } }
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
        }
        return Group {
            if isEditingPalette {
                // Drag to reorder: a selected run moves together.
                tile
                    .draggable("palette:\(index)") {
                        RoundedRectangle(cornerRadius: 5).fill(color.color).frame(width: 30, height: 30)
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
