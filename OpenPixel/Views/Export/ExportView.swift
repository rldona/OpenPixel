import SwiftUI

struct ExportView: View {
    let document: SpriteDocument
    @Environment(\.dismiss) private var dismiss
    @State private var format = ExportFormat.png
    @State private var scale = 4
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
                            .background(format == f ? Color(hex: 0x2A211E) : Theme.field, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(format == f ? Theme.accent : Theme.border, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Escala")
                    Picker("Escala", selection: $scale) {
                        ForEach(scales, id: \.self) { Text("\($0)×").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("Escalado por vecino más cercano: los píxeles siguen nítidos.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Vista previa")
                    PixelThumbnail(image: previewImage)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
                    HStack {
                        Text(fileURL?.lastPathComponent ?? "…")
                        Spacer()
                        Text(outputSize)
                    }
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                }

                Spacer()

                HStack {
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                    Spacer()
                    if let fileURL {
                        ShareLink(item: fileURL) {
                            Label("Compartir o guardar…", systemImage: "square.and.arrow.up")
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
            .background(Color(hex: 0x1A1A1F))
            .navigationTitle("Exportar «\(document.name)»")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            }
            .task(id: "\(format.rawValue)-\(scale)") { render() }
        }
    }

    private var previewImage: CGImage? {
        switch format {
        case .png, .gif: document.sprite.composite(frameIndex: format == .gif ? 0 : document.activeFrameIndex).makeCGImage()
        case .spriteSheet: Exporter.spriteSheet(document.sprite).makeCGImage()
        }
    }

    private var outputSize: String {
        let s = document.sprite
        let w = s.width * scale, h = s.height * scale
        switch format {
        case .png: return "\(w) × \(h) px"
        case .spriteSheet: return "\(w * s.frames.count) × \(h) px · \(s.frames.count) frames"
        case .gif: return "\(w) × \(h) px · \(s.frames.count) frames · \(s.totalDuration) ms"
        }
    }

    private func render() {
        do {
            fileURL = try Exporter.export(document.sprite, name: document.name, frameIndex: document.activeFrameIndex, format: format, scale: scale)
            errorMessage = nil
        } catch {
            fileURL = nil
            errorMessage = error.localizedDescription
        }
    }
}
