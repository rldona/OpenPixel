import SwiftUI

/// Aseprite's Export As, plus the sprite sheet, slices and the `.aseprite` file.
/// The last options used are remembered; the frames and layer are per sprite.
struct ExportView: View {
    let document: SpriteDocument
    @Environment(\.dismiss) private var dismiss
    @AppStorage("exportFormat") private var storedFormat = ExportFormat.png
    @AppStorage("exportScale") private var scale = 4
    /// Empty plays the tag's own direction.
    @AppStorage("exportDirection") private var directionRaw = ""
    @AppStorage("exportPixelRatio") private var applyPixelRatio = true
    @AppStorage("exportForTwitter") private var forTwitter = false
    /// A sprite sheet comes with Aseprite's JSON data (frames, tags, slices).
    @AppStorage("exportSheetData") private var includeData = false
    @State private var frames = ExportFrames.all
    @State private var layer: UUID?
    @State private var fileURLs: [URL] = []
    @State private var errorMessage: String?

    private let scales = [1, 2, 4, 6, 8, 10]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(formats) { f in formatCard(f) }
                    }
                    optionsSection
                    previewSection
                }
                .padding(28)
            }
            .safeAreaInset(edge: .bottom) { shareBar }
            .background(Theme.card)
            .navigationTitle(Text("Export “\(document.name)”"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task(id: options) { render() }
        }
    }

    // MARK: Options

    /// Slices are offered only when the sprite has some.
    private var formats: [ExportFormat] {
        ExportFormat.allCases.filter { $0 != .slices || !document.sprite.slices.isEmpty }
    }

    private var format: ExportFormat { formats.contains(storedFormat) ? storedFormat : .png }

    private var options: ExportOptions {
        ExportOptions(format: format, frames: frames, layer: layer, scale: scale,
                      direction: AnimationDirection(rawValue: directionRaw), applyPixelRatio: applyPixelRatio,
                      forTwitter: forTwitter, includeData: includeData)
    }

    private func formatCard(_ f: ExportFormat) -> some View {
        Button { storedFormat = f } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(f.title).font(.system(size: 15, weight: .semibold))
                Text(f.subtitle).font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .padding(.horizontal, 16)
            .background(format == f ? Theme.accentSoft : Theme.field, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(format == f ? Theme.accent : Theme.border, lineWidth: 2))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(format == f ? .isSelected : [])
    }

    @ViewBuilder
    private var optionsSection: some View {
        let sprite = document.sprite
        if format.isImage {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                if format.exportsFrames {
                    GridRow {
                        SectionLabel("Frames")
                        HStack(spacing: 10) {
                            framesMenu
                            if case .range(let from, let to) = frames { rangeChips(from: from, to: to) }
                        }
                    }
                }
                GridRow {
                    SectionLabel("Layers")
                    layerMenu
                }
                if format.playsFrames {
                    GridRow {
                        SectionLabel("Direction")
                        directionMenu
                    }
                }
                GridRow {
                    SectionLabel("Scale")
                    Picker("Scale", selection: $scale) {
                        ForEach(scales, id: \.self) { Text(verbatim: "\($0 * 100) %").tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                if !sprite.pixelRatio.isSquare {
                    toggle("Apply pixel ratio", isOn: $applyPixelRatio,
                           detail: Text("Pixels come out \(sprite.pixelRatio.title), as on the canvas."))
                }
                if format == .spriteSheet {
                    toggle("Include JSON data", isOn: $includeData,
                           detail: Text("Frames, durations, tags and slices, in Aseprite's format, for game engines."))
                } else {
                    toggle("Export for Twitter", isOn: $forTwitter,
                           detail: format == .gif ? Text("Adjusts the last frame's duration so Twitter plays the animation right.")
                                                  : Text("Keeps opaque images as PNG instead of JPEG on Twitter."))
                }
            }
        } else {
            Text("The whole sprite as Aseprite saves it, to keep working on it in Aseprite or in OpenPixel on another device.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
    }

    private var framesMenu: some View {
        let sprite = document.sprite
        return Menu {
            Picker("Frames", selection: $frames) {
                Text("All frames").tag(ExportFrames.all)
                Text("Current frame").tag(ExportFrames.current)
                ForEach(sprite.tags) { tag in
                    Text(verbatim: tag.name).tag(ExportFrames.tag(tag.id))
                }
                Text("Range…").tag(rangeSelection)
            }
        } label: {
            menuLabel(framesTitle)
        }
    }

    /// Selecting "Range…" keeps a range already chosen.
    private var rangeSelection: ExportFrames {
        if case .range = frames { return frames }
        return .range(from: 0, to: document.sprite.frames.count - 1)
    }

    private var framesTitle: Text {
        switch frames {
        case .all: Text("All frames")
        case .current: Text("Current frame")
        case .tag(let id): Text(verbatim: document.sprite.tags.first { $0.id == id }?.name ?? "")
        case .range: Text("Range…")
        }
    }

    private func rangeChips(from: Int, to: Int) -> some View {
        let count = document.sprite.frames.count
        return HStack(spacing: 6) {
            NumberChip(title: "From", value: Binding(get: { from + 1 }, set: { frames = .range(from: $0 - 1, to: max(to, $0 - 1)) }), range: 1...count)
            NumberChip(title: "To", value: Binding(get: { to + 1 }, set: { frames = .range(from: min(from, $0 - 1), to: $0 - 1) }), range: 1...count)
        }
    }

    private var layerMenu: some View {
        let layers = document.sprite.layers.filter { !$0.isGroup && !$0.isReference }.reversed()
        return Menu {
            Picker("Layers", selection: $layer) {
                Text("Visible layers").tag(UUID?.none)
                ForEach(Array(layers)) { layer in
                    Text(verbatim: layer.name).tag(Optional(layer.id))
                }
            }
        } label: {
            menuLabel(layer.flatMap { id in document.sprite.layers.first { $0.id == id } }.map { Text(verbatim: $0.name) } ?? Text("Visible layers"))
        }
    }

    private var directionMenu: some View {
        let tag = Exporter.tag(document.sprite, options)
        return Menu {
            Picker("Direction", selection: $directionRaw) {
                (Text("As the tag") + Text(verbatim: " (") + Text((tag?.direction ?? .forward).title) + Text(verbatim: ")")).tag("")
                ForEach(AnimationDirection.allCases) { direction in
                    Label(direction.title, systemImage: direction.systemImage).tag(direction.rawValue)
                }
            }
        } label: {
            menuLabel(AnimationDirection(rawValue: directionRaw).map { Text($0.title) } ?? Text("As the tag"))
        }
    }

    private func menuLabel(_ title: Text) -> some View {
        HStack(spacing: 6) {
            title.font(.system(size: 14, weight: .medium))
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Theme.chip, in: Capsule())
    }

    private func toggle(_ title: LocalizedStringKey, isOn: Binding<Bool>, detail: Text) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                detail.font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .tint(Theme.accent)
    }

    // MARK: Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Preview")
            PixelThumbnail(image: previewImage)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
            HStack {
                Text(verbatim: fileSummary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(verbatim: outputSize)
            }
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.muted)
        }
    }

    private var fileSummary: String {
        guard let first = fileURLs.first else { return "…" }
        if fileURLs.count > 3 { return "\(first.lastPathComponent) … \(fileURLs.last!.lastPathComponent)" }
        return fileURLs.map(\.lastPathComponent).joined(separator: " + ")
    }

    private var previewImage: CGImage? {
        let sprite = Exporter.isolating(document.sprite, layer: format.isImage ? layer : nil)
        let current = document.activeFrameIndex
        let image: PixelImage?
        switch format {
        case .png, .aseprite: image = sprite.composite(frameIndex: current)
        case .pngSequence, .gif: image = Exporter.playback(sprite, options, current: current).frames.first.map { sprite.composite(frameIndex: $0) }
        case .spriteSheet: image = Exporter.spriteSheet(sprite, frames: Exporter.frames(sprite, options, current: current))
        case .slices: image = Exporter.sliceImages(sprite, frameIndex: current).first?.image
        }
        let ratio = format.isImage && applyPixelRatio ? sprite.pixelRatio : .square
        return image?.scaled(x: ratio.width, y: ratio.height).makeCGImage()
    }

    private var outputSize: String {
        let s = document.sprite
        let (sx, sy) = Exporter.scales(s, options)
        let w = s.width * sx, h = s.height * sy
        switch format {
        case .png:
            return "\(w) × \(h) px"
        case .pngSequence:
            return "\(Exporter.playback(s, options, current: document.activeFrameIndex).frames.count) PNG · \(w) × \(h) px"
        case .gif:
            let frames = Exporter.playback(s, options, current: document.activeFrameIndex).frames
            let duration = frames.reduce(0) { $0 + s.frames[$1].duration }
            return "\(w) × \(h) px · \(frames.count) frames · \(duration) ms"
        case .spriteSheet:
            let count = Exporter.frames(s, options, current: document.activeFrameIndex).count
            return "\(w * count) × \(h) px · \(count) frames"
        case .slices:
            return "\(s.slices.count) PNG"
        case .aseprite:
            return "\(s.width) × \(s.height) px · \(s.frames.count) frames · \(s.layers.count) layers"
        }
    }

    // MARK: Sharing

    private var shareBar: some View {
        HStack {
            if let errorMessage { Text(verbatim: errorMessage).foregroundStyle(.red) }
            Spacer()
            if !fileURLs.isEmpty {
                ShareLink(items: fileURLs) {
                    Label("Share or save…", systemImage: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 20)
                        .frame(height: 48)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .background(Theme.card)
    }

    private func render() {
        do {
            fileURLs = try Exporter.exportFiles(document.sprite, name: document.name, frameIndex: document.activeFrameIndex, options: options)
            errorMessage = nil
        } catch {
            fileURLs = []
            errorMessage = error.localizedDescription
        }
    }
}
