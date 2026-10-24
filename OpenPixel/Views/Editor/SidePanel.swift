import SwiftUI
import UniformTypeIdentifiers

struct SidePanel: View {
    @Bindable var document: SpriteDocument
    let canvas: CanvasController
    @State private var editingPrimary = false
    @State private var editingSecondary = false
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

                VStack(spacing: 8) {
                    // What used to float over the canvas: tool, cel and tag.
                    infoRow("Tool", Text(document.tool.title)
                        + Text(verbatim: document.tool.usesBrush ? " · \(document.brushSize) px" : "")
                        + (document.symmetry.isOn ? Text(" + symmetry") : Text(verbatim: "")))
                    infoRow("Active cel", "\(document.activeLayer?.name ?? "–") · \(document.activeFrameIndex + 1)/\(document.structure.frames.count)")
                    if let tag = document.activeTag { infoRow("Tag", tag.name) }
                    infoRow("Layer opacity", "\(Int((document.activeLayer?.opacity ?? 1) * 100)) %")
                    infoRow("Animation", "\(document.structure.totalDuration) ms")
                }
                .padding(14)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
            }
            .padding(16)
        }
        // Background and divider run under the home indicator; the content stays in the safe area.
        .background {
            HStack(spacing: 0) {
                Rectangle().fill(Theme.border).frame(width: 1)
                Theme.panel
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

    /// Primary over secondary, like Aseprite's foreground and background colors.
    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Color")
            HStack(alignment: .top, spacing: 14) {
                ZStack(alignment: .topLeading) {
                    colorButton(document.secondary, size: 40, label: "Secondary color") { editingSecondary = true }
                        .offset(x: 30, y: 30)
                        .popover(isPresented: $editingSecondary) {
                            ColorEditor(color: $document.secondary, palette: document.structure.palette) { document.addToPalette($0) }
                                .presentationCompactAdaptation(.popover)
                        }
                    colorButton(document.primary, size: 52, label: "Primary color") { editingPrimary = true }
                        .popover(isPresented: $editingPrimary) {
                            ColorEditor(color: $document.primary, palette: document.structure.palette) { document.addToPalette($0) }
                                .presentationCompactAdaptation(.popover)
                        }
                }
                .frame(width: 72, height: 72, alignment: .topLeading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: document.primary.hex).font(.system(size: 15, weight: .medium, design: .monospaced))
                    if let index = document.paletteIndex(of: document.primary) {
                        Text("Palette index \(index)").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    } else {
                        Button { document.addToPalette(document.primary) } label: {
                            Label("Not in palette", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.accentText)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Adds it to the palette"))
                    }
                    Text("Secondary \(document.secondary.hex)").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            HStack {
                Button("Swap", systemImage: "arrow.left.arrow.right") { document.swapColors() }
                Spacer()
                Button("Replace…", systemImage: "drop.halffull") { document.isReplacingColor = true }
                    .accessibilityLabel(Text("Replace color…"))
            }
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
        }
    }

    private func colorButton(_ color: PixelColor, size: CGFloat, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Checkerboard(cell: 6)
                color.color
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.strongBorder))
            .overlay(RoundedRectangle(cornerRadius: 11).inset(by: 1).strokeBorder(Theme.panel, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(verbatim: color.hex))
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
            if isEditingPalette {
                paletteEditBar
            } else {
                Text("Tap a color to use it. Touch and hold for more options.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
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
            Group {
                if let range {
                    range.count == 1 ? Text("1 color selected") : Text("\(range.count) colors selected")
                } else {
                    Text("Tap colors to select them. Drag to reorder.")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.muted)
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

    private func infoRow(_ title: LocalizedStringKey, _ value: String) -> some View {
        infoRow(title, Text(verbatim: value))
    }

    private func infoRow(_ title: LocalizedStringKey, _ value: Text) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.muted)
            Spacer()
            value.lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 13))
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
