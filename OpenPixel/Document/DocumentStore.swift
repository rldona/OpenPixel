import CoreGraphics
import Foundation
import ImageIO
import Observation

struct SpriteSummary: Identifiable {
    let id: UUID
    var name: String
    var width: Int
    var height: Int
    var frameCount: Int
    var modified: Date
    var thumbnail: CGImage?
}

/// Sprites live as `.openpixel` JSON files in Documents/Sprites, which is
/// visible from the Files app.
@MainActor
@Observable
final class DocumentStore {
    private(set) var items: [SpriteSummary] = []
    let directory: URL

    nonisolated static let maxImportSize = 512

    init(directory: URL? = nil) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.directory = directory ?? documents.appendingPathComponent("Sprites", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        reload()
    }

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).openpixel")
    }

    private func read(_ url: URL) throws -> SpriteFile {
        try JSONDecoder().decode(SpriteFile.self, from: Data(contentsOf: url))
    }

    private static func summary(id: UUID, file: SpriteFile, modified: Date) -> SpriteSummary {
        SpriteSummary(
            id: id,
            name: file.name,
            width: file.sprite.width,
            height: file.sprite.height,
            frameCount: file.sprite.frames.count,
            modified: modified,
            thumbnail: file.sprite.composite(frameIndex: 0).makeCGImage()
        )
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        items = urls
            .filter { $0.pathExtension == "openpixel" }
            .compactMap { url -> SpriteSummary? in
                guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                      let file = try? read(url) else { return nil }
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return Self.summary(id: id, file: file, modified: modified)
            }
            .sorted { $0.modified > $1.modified }
    }

    func load(_ id: UUID) throws -> SpriteDocument {
        let file = try read(url(for: id))
        return SpriteDocument(id: id, name: file.name, sprite: file.sprite)
    }

    func save(_ document: SpriteDocument) throws {
        try write(document.file, id: document.id)
        document.markSaved()
    }

    private func write(_ file: SpriteFile, id: UUID) throws {
        let data = try JSONEncoder().encode(file)
        try data.write(to: url(for: id), options: .atomic)
        let summary = Self.summary(id: id, file: file, modified: Date())
        items.removeAll { $0.id == id }
        items.insert(summary, at: 0)
    }

    @discardableResult
    func create(name: String, sprite: Sprite) throws -> UUID {
        let id = UUID()
        try write(SpriteFile(name: name, sprite: sprite), id: id)
        return id
    }

    func rename(_ id: UUID, to name: String) throws {
        var file = try read(url(for: id))
        file.name = name
        try write(file, id: id)
    }

    func duplicate(_ id: UUID) throws {
        var file = try read(url(for: id))
        file.name += " (copia)"
        try write(file, id: UUID())
    }

    func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: url(for: id))
        items.removeAll { $0.id == id }
    }

    /// Creates a one-layer, one-frame sprite from a PNG.
    func importImage(at fileURL: URL) throws -> UUID {
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let image = PixelImage(cgImage: cgImage) else {
            throw ImportError.unreadable
        }
        guard image.width <= Self.maxImportSize, image.height <= Self.maxImportSize else {
            throw ImportError.tooLarge
        }
        var sprite = Sprite.blank(width: image.width, height: image.height, background: nil, palette: Palette.pico8.colors)
        sprite.layers[0].name = "Imagen"
        sprite.cels[CelKey(layer: sprite.layers[0].id, frame: sprite.frames[0].id)] = image
        return try create(name: fileURL.deletingPathExtension().lastPathComponent, sprite: sprite)
    }
}

enum ImportError: LocalizedError {
    case unreadable, tooLarge

    var errorDescription: String? {
        switch self {
        case .unreadable: "No se pudo leer la imagen."
        case .tooLarge: "La imagen es demasiado grande (máximo \(DocumentStore.maxImportSize) × \(DocumentStore.maxImportSize) px)."
        }
    }
}
