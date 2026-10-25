import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

/// An Aseprite extension (`.aseprite-extension`, a ZIP with a `package.json`).
/// OpenPixel takes its palettes and dithering matrices; themes, languages,
/// keys and scripts are Aseprite's own and are left out.
/// https://www.aseprite.org/docs/extensions/
struct AsepriteExtension: Codable, Identifiable, Hashable {
    /// The package's `name`.
    let id: String
    let displayName: String
    let version: String
    let author: String
    let palettes: [Palette]
    let ditheringMatrices: [GradientDither]
    /// What it contributes that OpenPixel can't use (themes, keys…).
    let leftOut: [String]
    /// Its scripts (plugins), by their path in the package, and the commands they add.
    var scripts: [String]? = nil
    var commands: [Command]? = nil

    /// A command a script adds with `plugin:newCommand`, run from … > Scripts.
    struct Command: Codable, Hashable, Identifiable {
        let id: String
        let title: String
        /// The script that adds it.
        let script: String
    }

    struct Palette: Codable, Hashable, Identifiable {
        let id: String
        let colors: [PixelColor]
    }

    enum Failure: LocalizedError {
        case noPackage
        case nothingToUse([String])
        case unsafePath(String)

        var errorDescription: String? {
            switch self {
            case .noPackage:
                L10n.string("This isn't an Aseprite extension: it has no package.json.")
            case .nothingToUse(let kinds):
                kinds.isEmpty
                    ? L10n.string("The extension has no palettes, dithering matrices or scripts.")
                    : L10n.string("The extension only has %@, which OpenPixel can't use. Palettes, dithering matrices and scripts are imported.", kinds.joined(separator: ", "))
            case .unsafePath(let path):
                L10n.string("The extension has a file outside its folder: %@", path)
            }
        }
    }

    /// Reads an extension's palettes and dithering matrices.
    static func read(_ data: Data) throws -> AsepriteExtension {
        let zip = try ZipArchive(data)
        // Some packages keep everything inside a folder.
        guard let packagePath = zip.paths.filter({ $0.hasSuffix("package.json") }).min(by: { $0.count < $1.count }),
              let packageData = try zip.data(at: packagePath),
              let package = try JSONSerialization.jsonObject(with: packageData) as? [String: Any] else { throw Failure.noPackage }
        let folder = String(packagePath.dropLast("package.json".count))
        let name = package["name"] as? String ?? UUID().uuidString
        let contributes = package["contributes"] as? [String: Any] ?? [:]

        func items(_ key: String) -> [[String: Any]] { contributes[key] as? [[String: Any]] ?? [] }
        func file(_ item: [String: Any]) throws -> (Data, String)? {
            guard let path = item["path"] as? String else { return nil }
            var relative = path
            while relative.hasPrefix("./") { relative.removeFirst(2) }
            guard let data = try zip.data(at: folder + relative) else { return nil }
            return (data, (relative as NSString).pathExtension)
        }

        var palettes: [Palette] = []
        for item in items("palettes") {
            guard let (data, ext) = try file(item), let colors = paletteColors(data, fileExtension: ext) else { continue }
            palettes.append(Palette(id: item["id"] as? String ?? "\(name) \(palettes.count + 1)", colors: colors))
        }
        var matrices: [GradientDither] = []
        for item in items("ditheringMatrices") {
            guard let (data, _) = try file(item), let levels = matrixLevels(data) else { continue }
            let id = item["id"] as? String ?? "\(name)-\(matrices.count + 1)"
            matrices.append(GradientDither(id: "\(name)/\(id)", name: item["name"] as? String ?? id, levels: levels))
        }
        let scripts = items("scripts").compactMap { $0["path"] as? String }.map { path in
            var relative = path
            while relative.hasPrefix("./") { relative.removeFirst(2) }
            return relative
        }
        let leftOut = ["themes", "languages", "keys"].filter { !items($0).isEmpty }
        guard !palettes.isEmpty || !matrices.isEmpty || !scripts.isEmpty else { throw Failure.nothingToUse(leftOut) }

        let author = (package["author"] as? [String: Any])?["name"] as? String ?? package["author"] as? String ?? ""
        return AsepriteExtension(
            id: name,
            displayName: package["displayName"] as? String ?? name,
            version: package["version"] as? String ?? "",
            author: author,
            palettes: palettes,
            ditheringMatrices: matrices,
            leftOut: leftOut,
            scripts: scripts.isEmpty ? nil : scripts
        )
    }

    /// The package's Lua files, by their path from the package's folder.
    static func luaFiles(in data: Data) throws -> [String: Data] {
        let zip = try ZipArchive(data)
        guard let packagePath = zip.paths.filter({ $0.hasSuffix("package.json") }).min(by: { $0.count < $1.count }) else { throw Failure.noPackage }
        let folder = String(packagePath.dropLast("package.json".count))
        var files: [String: Data] = [:]
        for path in zip.paths where path.hasPrefix(folder) && path.lowercased().hasSuffix(".lua") {
            let relative = String(path.dropFirst(folder.count))
            guard !relative.split(separator: "/").contains("..") else { throw Failure.unsafePath(relative) }
            files[relative] = try zip.data(at: path)
        }
        return files
    }

    /// Palette files (.gpl, .pal, .hex, images) or a sprite's palette (.aseprite).
    private static func paletteColors(_ data: Data, fileExtension: String) -> [PixelColor]? {
        if ["aseprite", "ase"].contains(fileExtension.lowercased()) {
            let palette = (try? AsepriteFile.read(data))?.palette ?? []
            return palette.isEmpty ? nil : palette
        }
        return PaletteFile.colors(from: data, fileExtension: fileExtension)
    }

    /// A matrix image's levels: each pixel's gray value, by row.
    private static func matrixLevels(_ data: Data) -> [[Int]]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let image = PixelImage(cgImage: cgImage),
              image.width > 0, image.height > 0, image.width <= 64, image.height <= 64 else { return nil }
        return (0..<image.height).map { y in (0..<image.width).map { x in Int(image[x, y].r) } }
    }
}

/// The extensions installed, kept in Application Support.
@MainActor @Observable
final class ExtensionStore {
    static let shared = ExtensionStore()

    private(set) var installed: [AsepriteExtension] = []

    private let file: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("extensions.json")
    }()

    private init() {
        if let data = try? Data(contentsOf: file) {
            installed = (try? JSONDecoder().decode([AsepriteExtension].self, from: data)) ?? []
        }
    }

    var palettes: [AsepriteExtension.Palette] { installed.flatMap(\.palettes) }

    /// Where an extension's scripts are kept.
    func folder(of package: AsepriteExtension) -> URL {
        file.deletingLastPathComponent().appendingPathComponent("Extensions")
            .appendingPathComponent(package.id.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "..", with: "_"))
    }
    var ditheringMatrices: [GradientDither] { installed.flatMap(\.ditheringMatrices) }

    /// Installs an extension, replacing an earlier version of it.
    @discardableResult
    func install(_ data: Data) throws -> AsepriteExtension {
        var package = try AsepriteExtension.read(data)
        if let scripts = package.scripts {
            // The scripts go in the extension's own folder, the only place `dofile` reads.
            let folder = folder(of: package)
            try? FileManager.default.removeItem(at: folder)
            for (path, contents) in try AsepriteExtension.luaFiles(in: data) {
                let url = folder.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try contents.write(to: url, options: .atomic)
            }
            package.commands = scripts.flatMap { script in
                ScriptEngine.commands(of: script, in: folder, name: package.displayName).map {
                    AsepriteExtension.Command(id: $0.id, title: $0.title, script: script)
                }
            }
        }
        installed.removeAll { $0.id == package.id }
        installed.append(package)
        installed.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        try save()
        return package
    }

    func install(contentsOf url: URL) throws -> AsepriteExtension {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try install(Data(contentsOf: url))
    }

    func remove(_ id: AsepriteExtension.ID) {
        if let package = installed.first(where: { $0.id == id }) { try? FileManager.default.removeItem(at: folder(of: package)) }
        installed.removeAll { $0.id == id }
        try? save()
    }

    private func save() throws {
        try JSONEncoder().encode(installed).write(to: file, options: .atomic)
    }
}

extension UTType {
    /// Aseprite's extension packages (declared in Info.plist).
    static let asepriteExtension = UTType(importedAs: "org.aseprite.extension", conformingTo: .zip)
}
