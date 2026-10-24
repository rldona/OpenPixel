import Foundation
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case png, spriteSheet, gif, slices

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .png: "PNG"
        case .spriteSheet: "Sprite sheet"
        case .gif: "Animated GIF"
        case .slices: "Slices"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .png: "Current frame"
        case .spriteSheet: "All frames in a row"
        case .gif: "With each frame's duration"
        case .slices: "Each slice as a PNG"
        }
    }

    var fileExtension: String { self == .gif ? "gif" : "png" }
}

enum ExportError: LocalizedError {
    case encodingFailed

    var errorDescription: String? { L10n.string("Couldn't create the image.") }
}

enum Exporter {
    /// Frames side by side, left to right. `frames` defaults to all of them.
    static func spriteSheet(_ sprite: Sprite, frames: [Int]? = nil) -> PixelImage {
        let frames = frames ?? Array(sprite.frames.indices)
        var sheet = PixelImage(width: sprite.width * frames.count, height: sprite.height)
        for (column, index) in frames.enumerated() {
            sheet.paste(sprite.composite(frameIndex: index), at: column * sprite.width, 0)
        }
        return sheet
    }

    /// Frames a GIF plays and how many times it loops (0 = forever):
    /// the tag's cycle, honouring its direction, or every frame in order.
    static func animation(_ sprite: Sprite, tag: FrameTag?) -> (frames: [Int], loopCount: Int) {
        guard let tag else { return (Array(sprite.frames.indices), 0) }
        return (Playback.cycle(from: tag.from, to: tag.to, direction: tag.direction), tag.repeatCount)
    }

    static func pngData(_ image: PixelImage) throws -> Data {
        guard let cgImage = image.makeCGImage() else { throw ExportError.encodingFailed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ExportError.encodingFailed
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.encodingFailed }
        return data as Data
    }

    static func gifData(_ sprite: Sprite, frames: [Int]? = nil, loopCount: Int = 0, scale: Int) throws -> Data {
        let frames = frames ?? Array(sprite.frames.indices)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw ExportError.encodingFailed
        }
        let fileProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loopCount]] as CFDictionary
        CGImageDestinationSetProperties(destination, fileProperties)
        for index in frames {
            guard let cgImage = sprite.composite(frameIndex: index).scaled(by: scale).makeCGImage() else {
                throw ExportError.encodingFailed
            }
            let delay = Double(sprite.frames[index].duration) / 1000
            let frameProperties = [kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay
            ]] as CFDictionary
            CGImageDestinationAddImage(destination, cgImage, frameProperties)
        }
        guard CGImageDestinationFinalize(destination) else { throw ExportError.encodingFailed }
        return data as Data
    }

    /// Aseprite's sprite sheet data (the JSON its CLI `--data` and Export
    /// Sprite Sheet write, "array" layout): each frame's place in the sheet
    /// and duration, plus tags and slices, in the sheet's (scaled) pixels.
    static func sheetData(_ sprite: Sprite, frames: [Int], scale: Int, imageName: String, baseName: String) throws -> Data {
        let w = sprite.width * scale, h = sprite.height * scale
        func rect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int) -> [String: Int] { ["x": x, "y": y, "w": rw, "h": rh] }
        let frameEntries: [[String: Any]] = frames.enumerated().map { column, index in
            [
                "filename": "\(baseName) \(index).png",
                "frame": rect(column * w, 0, w, h),
                "rotated": false,
                "trimmed": false,
                "spriteSourceSize": rect(0, 0, w, h),
                "sourceSize": ["w": w, "h": h],
                "duration": sprite.frames[index].duration
            ]
        }
        // Tags and slice keys are numbered within the exported frames.
        let position = Dictionary(uniqueKeysWithValues: frames.enumerated().map { ($1, $0) })
        let tags: [[String: Any]] = sprite.tags.compactMap { tag in
            guard let from = position[tag.from], let to = position[tag.to] else { return nil }
            let direction = ["forward": "forward", "reverse": "reverse", "pingPong": "pingpong", "pingPongReverse": "pingpong_reverse"][tag.direction.rawValue] ?? "forward"
            return ["name": tag.name, "from": from, "to": to, "direction": direction, "repeat": "\(tag.repeatCount)"]
        }
        let slices: [[String: Any]] = sprite.slices.map { slice in
            var keys: [[String: Any]] = []
            var last: SliceKey?
            for (column, index) in frames.enumerated() {
                guard let key = slice.key(at: index, frames: sprite.frames), key != last else { continue }
                last = key
                let b = key.bounds
                var entry: [String: Any] = ["frame": column, "bounds": rect(b.minX * scale, b.minY * scale, b.width * scale, b.height * scale)]
                if let c = key.center { entry["center"] = rect(c.minX * scale, c.minY * scale, c.width * scale, c.height * scale) }
                if let p = key.pivot { entry["pivot"] = ["x": p.x * scale, "y": p.y * scale] }
                keys.append(entry)
            }
            let c = slice.color
            return ["name": slice.name, "color": String(format: "#%02x%02x%02x%02x", c.r, c.g, c.b, c.a), "keys": keys]
        }
        let meta: [String: Any] = [
            "app": "https://github.com/rldona/OpenPixel",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
            "image": imageName,
            "format": "RGBA8888",
            "size": ["w": w * frames.count, "h": h],
            "scale": "\(scale)",
            "frameTags": tags,
            "layers": sprite.layers.filter { !$0.isReference && !$0.isGroup }.map { ["name": $0.name, "opacity": Int(($0.opacity * 255).rounded()), "blendMode": $0.blendMode.rawValue] },
            "slices": slices
        ]
        return try JSONSerialization.data(withJSONObject: ["frames": frameEntries, "meta": meta], options: [.prettyPrinted, .sortedKeys])
    }

    /// Each slice of a frame, cropped (Aseprite's --split-slices), with its name.
    static func sliceImages(_ sprite: Sprite, frameIndex: Int) -> [(name: String, image: PixelImage)] {
        let image = sprite.composite(frameIndex: frameIndex)
        return sprite.slices.compactMap { slice in
            guard let key = slice.key(at: frameIndex, frames: sprite.frames),
                  let rect = key.bounds.clipped(width: sprite.width, height: sprite.height) else { return nil }
            return (slice.name, image.cropped(to: rect))
        }
    }

    /// Writes the export to temporary files ready to share: the image, plus
    /// the JSON data for a sprite sheet with `includeData`, or one PNG per slice.
    static func exportFiles(_ sprite: Sprite, name: String, frameIndex: Int, format: ExportFormat, scale: Int, tag: FrameTag? = nil, includeData: Bool = false) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var safeName = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        if safeName.isEmpty { safeName = "sprite" }
        switch format {
        case .slices:
            var used: Set<String> = []
            return try sliceImages(sprite, frameIndex: frameIndex).map { slice in
                var file = "\(safeName)-\(slice.name)".components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
                while used.contains(file) { file += "-2" }
                used.insert(file)
                let url = directory.appendingPathComponent("\(file).png")
                try pngData(slice.image.scaled(by: scale)).write(to: url, options: .atomic)
                return url
            }
        case .spriteSheet where includeData:
            let image = try export(sprite, name: name, frameIndex: frameIndex, format: format, scale: scale, tag: tag)
            let frames = tag.map { Array($0.from...$0.to) } ?? Array(sprite.frames.indices)
            let json = try sheetData(sprite, frames: frames, scale: scale, imageName: image.lastPathComponent, baseName: safeName)
            let url = image.deletingPathExtension().appendingPathExtension("json")
            try json.write(to: url, options: .atomic)
            return [image, url]
        default:
            return [try export(sprite, name: name, frameIndex: frameIndex, format: format, scale: scale, tag: tag)]
        }
    }

    /// Writes the export to a temporary file ready to share.
    /// `tag` limits the sprite sheet and the GIF to that tag's frames.
    static func export(_ sprite: Sprite, name: String, frameIndex: Int, format: ExportFormat, scale: Int, tag: FrameTag? = nil) throws -> URL {
        let data: Data
        switch format {
        case .png:
            data = try pngData(sprite.composite(frameIndex: frameIndex).scaled(by: scale))
        case .spriteSheet:
            let frames = tag.map { Array($0.from...$0.to) }
            data = try pngData(spriteSheet(sprite, frames: frames).scaled(by: scale))
        case .gif:
            let animation = animation(sprite, tag: tag)
            data = try gifData(sprite, frames: animation.frames, loopCount: animation.loopCount, scale: scale)
        case .slices:
            guard let first = sliceImages(sprite, frameIndex: frameIndex).first else { throw ExportError.encodingFailed }
            data = try pngData(first.image.scaled(by: scale))
        }
        var safeName = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        if let tag, format != .png { safeName += "-\(tag.name)" }
        let suffix = format == .spriteSheet ? "-sheet" : ""
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(safeName.isEmpty ? "sprite" : safeName)\(suffix).\(format.fileExtension)")
        try data.write(to: url, options: .atomic)
        return url
    }
}
