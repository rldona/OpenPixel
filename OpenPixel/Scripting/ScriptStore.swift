import Foundation
import Observation
import UniformTypeIdentifiers

/// The scripts the user added (Aseprite's File > Scripts), kept in
/// Application Support/Scripts. Only scripts the user picks from Files are
/// added: OpenPixel never downloads code.
@MainActor @Observable
final class ScriptStore {
    static let shared = ScriptStore()

    struct Script: Identifiable, Hashable {
        let url: URL
        var id: URL { url }
        var name: String { url.deletingPathExtension().lastPathComponent }
    }

    private(set) var scripts: [Script] = []

    private let folder: URL = {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Scripts")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    private init() { reload() }

    private func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        scripts = files.filter { $0.pathExtension.lowercased() == "lua" }
            .map { Script(url: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Copies a script in; one with the same name is replaced.
    @discardableResult
    func install(contentsOf url: URL) throws -> Script {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard String(data: data, encoding: .utf8) != nil else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        let destination = folder.appendingPathComponent(url.deletingPathExtension().lastPathComponent).appendingPathExtension("lua")
        try data.write(to: destination, options: .atomic)
        reload()
        return Script(url: destination)
    }

    func remove(_ script: Script) {
        try? FileManager.default.removeItem(at: script.url)
        reload()
    }

    func source(of script: Script) throws -> String {
        try String(contentsOf: script.url, encoding: .utf8)
    }
}

extension UTType {
    /// Lua scripts (declared in Info.plist).
    static let luaScript = UTType(importedAs: "org.lua.script", conformingTo: .sourceCode)
}
