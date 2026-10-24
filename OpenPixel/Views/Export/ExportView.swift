import SwiftUI

struct ExportView: View {
    let document: SpriteDocument
    @Environment(\.dismiss) private var dismiss
    @State private var format = ExportFormat.png
    @State private var scale = 4
    /// nil exports every frame.
    @State private var tagID: UUID?
    @State private var fileURL: URL?
    @State private var errorMessage: String?

    private let scales = [1, 2, 4, 6, 8, 10]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    ForEach(ExportFormat.allCases) { f in
                        Button { format = f } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(f.title).font(.system(size: 15, weight: .semibold))
                                Text(f.subtitle).font(.system(size: 12)).foregroundStyle(Theme.muted)
                            }
                            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                            .padding(.horizontal, 16)
                            .background(format == f ? Theme.accentSoft : Theme.field, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(format == f ? Theme.accent : Theme.border, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if format != .png && !document.sprite.tags.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel("Frames")
                        Picker("Frames", selection: $tagID) {
                            Text("All").tag(UUID?.none)
                            ForEach(document.sprite.tags) { tag in
                                Text(verbatim: tag.name).tag(Optional(tag.id))
                            }
                        }
                        .pickerStyle(.segmented)
                        if let tag, format == .gif {
                            (Text(tag.direction.title) + Text(verbatim: " · ") + (tag.repeatCount == 0 ? Text("loops forever") : Text("plays \(tag.repeatCount) times")))
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Scale")
                    Picker("Scale", selection: $scale) {
                        ForEach(scales, id: \.self) { Text(verbatim: "\($0)×").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("Nearest-neighbor scaling keeps pixels sharp.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Preview")
                    PixelThumbnail(image: previewImage)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
                    HStack {
                        Text(verbatim: fileURL?.lastPathComponent ?? "…")
                        Spacer()
                        Text(verbatim: outputSize)
                    }
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                }

                Spacer()

                HStack {
                    if let errorMessage { Text(verbatim: errorMessage).foregroundStyle(.red) }
                    Spacer()
                    if let fileURL {
                        ShareLink(item: fileURL) {
                            Label("Share or save…", systemImage: "square.and.arrow.up")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.onAccent)
                                .padding(.horizontal, 20)
                                .frame(height: 48)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            .padding(28)
            .background(Theme.card)
            .navigationTitle(Text("Export “\(document.name)”"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task(id: "\(format.rawValue)-\(scale)-\(tagID?.uuidString ?? "all")") { render() }
        }
    }

    private var tag: FrameTag? {
        format == .png ? nil : document.sprite.tags.first { $0.id == tagID }
    }

    private var previewImage: CGImage? {
        let sprite = document.sprite
        switch format {
        case .png: return sprite.composite(frameIndex: document.activeFrameIndex).makeCGImage()
        case .gif: return sprite.composite(frameIndex: Exporter.animation(sprite, tag: tag).frames[0]).makeCGImage()
        case .spriteSheet: return Exporter.spriteSheet(sprite, frames: tag.map { Array($0.from...$0.to) }).makeCGImage()
        }
    }

    private var outputSize: String {
        let s = document.sprite
        let w = s.width * scale, h = s.height * scale
        switch format {
        case .png:
            return "\(w) × \(h) px"
        case .spriteSheet:
            let count = tag?.frameCount ?? s.frames.count
            return "\(w * count) × \(h) px · \(count) frames"
        case .gif:
            let frames = Exporter.animation(s, tag: tag).frames
            let duration = frames.reduce(0) { $0 + s.frames[$1].duration }
            return "\(w) × \(h) px · \(frames.count) frames · \(duration) ms"
        }
    }

    private func render() {
        do {
            fileURL = try Exporter.export(document.sprite, name: document.name, frameIndex: document.activeFrameIndex, format: format, scale: scale, tag: tag)
            errorMessage = nil
        } catch {
            fileURL = nil
            errorMessage = error.localizedDescription
        }
    }
}
