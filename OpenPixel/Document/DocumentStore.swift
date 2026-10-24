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

    /// The frames a gallery card plays, with their durations in ms.
    struct Animation: @unchecked Sendable {
        let frames: [CGImage]
        let durations: [Int]
    }

    @ObservationIgnored private var animations: [UUID: (modified: Date, animation: Animation)] = [:]

    /// An animated sprite's frames for its gallery card, made in the background
    /// the first time the card shows and kept until the sprite changes.
    func animation(for item: SpriteSummary) async -> Animation? {
        guard item.frameCount > 1 else { return nil }
        if let cached = animations[item.id], cached.modified == item.modified { return cached.animation }
        let url = url(for: item.id)
        let animation = await Task.detached(priority: .utility) { () -> Animation? in
            guard let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(SpriteFile.self, from: data) else { return nil }
            let sprite = file.sprite
            // Keep big, long animations to a few megabytes per card.
            let limit = max(2, 16_000_000 / max(1, sprite.width * sprite.height))
            let indices = Array(sprite.frames.indices.prefix(limit))
            let frames = indices.compactMap { sprite.composite(frameIndex: $0).makeCGImage() }
            guard frames.count == indices.count else { return nil }
            return Animation(frames: frames, durations: indices.map { sprite.frames[$0].duration })
        }.value
        if let animation { animations[item.id] = (item.modified, animation) }
        return animation
    }

    func load(_ id: UUID) throws -> SpriteDocument {
        let file = try read(url(for: id))
        return SpriteDocument(id: id, name: file.name, sprite: file.sprite)
    }

    /// Saves in the background: encoding a big sprite takes long enough to
    /// stutter drawing if done on the main thread. Saves of the same sprite
    /// are queued so an older one can never overwrite a newer one.
    func save(_ document: SpriteDocument) {
        let file = document.file, id = document.id, url = url(for: id)
        document.markSaved()
        let previous = pendingSaves[id]
        let task = Task.detached(priority: .utility) {
            await previous?.value
            do {
                try JSONEncoder().encode(file).write(to: url, options: .atomic)
            } catch {
                print("OpenPixel: could not save \(url.lastPathComponent): \(error)")
            }
        }
        pendingSaves[id] = task
        // The gallery isn't on screen while editing: its card is refreshed when it
        // shows again (`flush`), not on every autosave, which would rebuild it each stroke.
        pendingFiles[id] = file
    }

    @ObservationIgnored private var pendingSaves: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var pendingFiles: [UUID: SpriteFile] = [:]

    /// Waits for background saves, so the gallery reads the latest files,
    /// and brings the saved sprites' cards up to date.
    func flush() async {
        let tasks = pendingSaves.values
        pendingSaves = [:]
        for task in tasks { await task.value }
        let files = pendingFiles
        pendingFiles = [:]
        for (id, file) in files { updateSummary(Self.summary(id: id, file: file, modified: Date())) }
    }

    private func write(_ file: SpriteFile, id: UUID) throws {
        let data = try JSONEncoder().encode(file)
        try data.write(to: url(for: id), options: .atomic)
        updateSummary(Self.summary(id: id, file: file, modified: Date()))
    }

    private func updateSummary(_ summary: SpriteSummary) {
        items.removeAll { $0.id == summary.id }
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
        file.name += L10n.string(" (copy)")
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
        var sprite = Sprite.blank(width: image.width, height: image.height, background: nil, palette: Palette.newSpriteDefault.colors)
        sprite.layers[0].name = L10n.string("Image")
        sprite.cels[CelKey(layer: sprite.layers[0].id, frame: sprite.frames[0].id)] = image
        return try create(name: fileURL.deletingPathExtension().lastPathComponent, sprite: sprite)
    }
}

enum ImportError: LocalizedError {
    case unreadable, tooLarge

    var errorDescription: String? {
        switch self {
        case .unreadable: L10n.string("Couldn't read the image.")
        case .tooLarge: L10n.string("The image is too large (maximum %d × %d px).", DocumentStore.maxImportSize, DocumentStore.maxImportSize)
        }
    }
}
