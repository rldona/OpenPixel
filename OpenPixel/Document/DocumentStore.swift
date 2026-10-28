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

/// A folder on the home screen, to keep projects together. Folders can
/// hold folders too.
struct ProjectFolder: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    /// The folder it's in; nil on the home screen.
    var parent: UUID?
}

/// Sprites live as `.openpixel` JSON files in Documents/Sprites, which is
/// visible from the Files app. Folders are an index beside them
/// (`folders.json`), so the sprite files never move.
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
        loadFolders()
    }

    // MARK: Folders

    private(set) var folders: [ProjectFolder] = []
    /// The folder each project is in; projects left out are on the home screen.
    private(set) var folderOf: [UUID: UUID] = [:]
    /// The order projects were dragged into, per folder.
    private var order: [UUID: [UUID]] = [:]

    private struct FolderIndex: Codable {
        var folders: [ProjectFolder]
        var projects: [String: UUID]
        var order: [String: [UUID]]?
    }

    private var foldersURL: URL { directory.appendingPathComponent("folders.json") }

    /// Reads the index, forgetting projects and folders that are gone.
    private func loadFolders() {
        guard let data = try? Data(contentsOf: foldersURL),
              let index = try? JSONDecoder().decode(FolderIndex.self, from: data) else {
            folders = []
            folderOf = [:]
            order = [:]
            return
        }
        folders = index.folders
        let ids = Set(items.map(\.id)), folderIDs = Set(folders.map(\.id))
        // A folder whose parent is gone, or that ended up inside itself, goes to the home screen.
        for i in folders.indices {
            if let parent = folders[i].parent, !folderIDs.contains(parent) || path(to: parent).contains(where: { $0.id == folders[i].id }) {
                folders[i].parent = nil
            }
        }
        folderOf = Dictionary(uniqueKeysWithValues: index.projects.compactMap { key, folder in
            guard let id = UUID(uuidString: key), ids.contains(id), folderIDs.contains(folder) else { return nil }
            return (id, folder)
        })
        order = Dictionary(uniqueKeysWithValues: (index.order ?? [:]).compactMap { key, ids in
            UUID(uuidString: key).flatMap { folderIDs.contains($0) ? ($0, ids) : nil }
        })
    }

    private func saveFolders() throws {
        let index = FolderIndex(folders: folders,
                                projects: Dictionary(uniqueKeysWithValues: folderOf.map { ($0.key.uuidString, $0.value) }),
                                order: Dictionary(uniqueKeysWithValues: order.map { ($0.key.uuidString, $0.value) }))
        try JSONEncoder().encode(index).write(to: foldersURL, options: .atomic)
    }

    /// The projects in `folder` in the order they were dragged into, the
    /// ones not placed yet (new, or just moved in) first; on the home
    /// screen (nil), newest first.
    func items(in folder: UUID?) -> [SpriteSummary] {
        let list = items.filter { folderOf[$0.id] == folder }
        guard let folder, let order = order[folder] else { return list }
        var position: [UUID: Int] = [:]
        for (i, id) in order.enumerated() where position[id] == nil { position[id] = i }
        return list.filter { position[$0.id] == nil }
            + list.compactMap { item in position[item.id].map { (item, $0) } }.sorted { $0.1 < $1.1 }.map(\.0)
    }

    /// Drags a project in a folder to where `target` is: it lands after it
    /// when it comes from before, before it when it comes from after.
    func reorder(_ id: UUID, to target: UUID, in folder: UUID) throws {
        var ids = items(in: folder).map(\.id)
        guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target), from != to else { return }
        ids.remove(at: from)
        ids.insert(id, at: to)
        order[folder] = ids
        try saveFolders()
    }

    func folder(_ id: UUID) -> ProjectFolder? { folders.first { $0.id == id } }

    /// The folders in `parent`, or on the home screen when it's nil.
    func folders(in parent: UUID?) -> [ProjectFolder] {
        folders.filter { $0.parent == parent }
    }

    /// The folders from the home screen down to `id`, `id` last.
    func path(to id: UUID) -> [ProjectFolder] {
        var path: [ProjectFolder] = [], next: UUID? = id
        while let current = next, let folder = folder(current), !path.contains(folder) {
            path.insert(folder, at: 0)
            next = folder.parent
        }
        return path
    }

    /// The projects in `id` and in every folder inside it, newest first.
    func allItems(in id: UUID) -> [SpriteSummary] {
        let inside = Set(folders.filter { path(to: $0.id).contains { $0.id == id } }.map(\.id))
        return items.filter { folderOf[$0.id].map(inside.contains) ?? false }
    }

    /// A new folder, first in `parent`, with a name no folder beside it has.
    @discardableResult
    func createFolder(name: String, in parent: UUID? = nil) throws -> UUID {
        let taken = Set(folders(in: parent).map(\.name))
        var unique = name, n = 2
        while taken.contains(unique) { unique = "\(name) \(n)"; n += 1 }
        let folder = ProjectFolder(id: UUID(), name: unique, parent: parent.flatMap { self.folder($0) }?.id)
        folders.insert(folder, at: 0)
        try saveFolders()
        return folder.id
    }

    /// Puts a folder in `parent` (nil: the home screen). A folder can't go
    /// inside itself or a folder within it.
    func moveFolder(_ id: UUID, to parent: UUID?) throws {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return }
        if let parent {
            guard folder(parent) != nil, !path(to: parent).contains(where: { $0.id == id }) else { return }
        }
        folders[i].parent = parent
        try saveFolders()
    }

    func renameFolder(_ id: UUID, to name: String) throws {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].name = name
        try saveFolders()
    }

    /// Deletes the folder only: its projects and folders go up to the
    /// folder it was in (or the home screen).
    func deleteFolder(_ id: UUID) throws {
        guard let deleted = folder(id) else { return }
        folders.removeAll { $0.id == id }
        order[id] = nil
        for i in folders.indices where folders[i].parent == id { folders[i].parent = deleted.parent }
        for (project, folder) in folderOf where folder == id { folderOf[project] = deleted.parent }
        try saveFolders()
    }

    /// Puts projects in `folder`, or back on the home screen when it's nil.
    func move(_ ids: [UUID], to folder: UUID?) throws {
        guard folder.map({ self.folder($0) != nil }) ?? true else { return }
        for id in ids where items.contains(where: { $0.id == id }) { folderOf[id] = folder }
        try saveFolders()
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

    @ObservationIgnored private var opened: SpriteDocument?

    /// The document the editor opens, ready for its first frame so there's
    /// no blank screen on the way in. Reading takes a few milliseconds; the
    /// latest save is used even before it reaches the disk. The editor asks
    /// again while it shows, so the document is kept until the gallery is
    /// back (`forgetOpened`).
    func open(_ id: UUID) throws -> SpriteDocument {
        if let opened, opened.id == id { return opened }
        let file = try pendingFiles[id] ?? read(url(for: id))
        let document = SpriteDocument(id: id, name: file.name, sprite: file.sprite)
        opened = document
        return document
    }

    func forgetOpened() { opened = nil }

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
        // A save that failed leaves no file: no card for it.
        for (id, file) in files where FileManager.default.fileExists(atPath: url(for: id).path) {
            updateSummary(Self.summary(id: id, file: file, modified: Date()))
        }
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

    /// New sprites and imports get a name no other sprite has: a second
    /// "Untitled" becomes "Untitled 2", then "Untitled 3"…
    @discardableResult
    func create(name: String, sprite: Sprite, in folder: UUID? = nil) throws -> UUID {
        let id = UUID()
        try write(SpriteFile(name: uniqueName(name), sprite: sprite), id: id)
        if let folder { try move([id], to: folder) }
        return id
    }

    func uniqueName(_ name: String) -> String {
        let taken = Set(items.map(\.name))
        guard taken.contains(name) else { return name }
        var n = 2
        while taken.contains("\(name) \(n)") { n += 1 }
        return "\(name) \(n)"
    }

    func rename(_ id: UUID, to name: String) throws {
        var file = try read(url(for: id))
        file.name = name
        try write(file, id: id)
    }

    /// The copy goes in the same folder.
    func duplicate(_ id: UUID) throws {
        var file = try read(url(for: id))
        file.name += L10n.string(" (copy)")
        let copy = UUID()
        try write(file, id: copy)
        if let folder = folderOf[id] { try move([copy], to: folder) }
    }

    /// Deleting forgets the sprite's pending card too, or the next `flush`
    /// would bring a card back for a file that's gone. A save still running
    /// is let finish and its file removed after it.
    func delete(_ id: UUID) throws {
        pendingFiles[id] = nil
        items.removeAll { $0.id == id }
        if folderOf.removeValue(forKey: id) != nil { try? saveFolders() }
        let url = url(for: id)
        if let pending = pendingSaves.removeValue(forKey: id) {
            Task {
                await pending.value
                try? FileManager.default.removeItem(at: url)
            }
            return
        }
        // Already gone: nothing left to delete.
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    /// Makes a project from an Aseprite file or an image; an animated GIF
    /// or PNG keeps its frames and their durations.
    func importFile(at fileURL: URL, into folder: UUID? = nil) throws -> UUID {
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer { if accessing { fileURL.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: fileURL)
        let name = fileURL.deletingPathExtension().lastPathComponent
        if ["aseprite", "ase"].contains(fileURL.pathExtension.lowercased()) {
            return try create(name: name, sprite: AsepriteFile.read(data), in: folder)
        }
        return try create(name: name, sprite: Self.sprite(fromImage: data), in: folder)
    }

    /// One layer, with a frame for each frame of the image.
    nonisolated static func sprite(fromImage data: Data) throws -> Sprite {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            throw ImportError.unreadable
        }
        var sprite: Sprite?
        for index in 0..<CGImageSourceGetCount(source) {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil), let image = PixelImage(cgImage: cgImage) else {
                throw ImportError.unreadable
            }
            if sprite == nil {
                guard image.width <= maxImportSize, image.height <= maxImportSize else { throw ImportError.tooLarge }
                var first = Sprite.blank(width: image.width, height: image.height, background: nil, palette: Palette.newSpriteDefault.colors)
                first.layers[0].name = L10n.string("Image")
                sprite = first
            } else {
                sprite!.insertFrame(Frame(), at: index)
            }
            guard image.width == sprite!.width, image.height == sprite!.height else { throw ImportError.unreadable }
            if let delay = frameDelay(source, at: index) { sprite!.frames[index].duration = max(10, Int((delay * 1000).rounded())) }
            if !image.isEmpty { sprite!.cels[CelKey(layer: sprite!.layers[0].id, frame: sprite!.frames[index].id)] = image }
        }
        return sprite!
    }

    /// A GIF's or animated PNG's delay for one frame, in seconds.
    nonisolated static func frameDelay(_ source: CGImageSource, at index: Int) -> Double? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else { return nil }
        let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        let delay = gif?[kCGImagePropertyGIFUnclampedDelayTime] ?? gif?[kCGImagePropertyGIFDelayTime]
            ?? png?[kCGImagePropertyAPNGUnclampedDelayTime] ?? png?[kCGImagePropertyAPNGDelayTime]
        return (delay as? Double).flatMap { $0 > 0 ? $0 : nil }
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
