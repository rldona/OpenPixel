import Foundation
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case png, pngSequence, gif, spriteSheet, slices, aseprite

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .png: "PNG"
        case .pngSequence: "PNG sequence"
        case .gif: "Animated GIF"
        case .spriteSheet: "Sprite sheet"
        case .slices: "Slices"
        case .aseprite: "Aseprite"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .png: "Current frame"
        case .pngSequence: "One file per frame"
        case .gif: "With each frame's duration"
        case .spriteSheet: "Frames in a row"
        case .slices: "Each slice as a PNG"
        case .aseprite: "Layers, frames, tags and slices"
        }
    }

    var fileExtension: String {
        switch self {
        case .gif: "gif"
        case .aseprite: "aseprite"
        default: "png"
        }
    }

    /// Exports a choice of frames (Aseprite's Frames field).
    var exportsFrames: Bool { [.pngSequence, .gif, .spriteSheet].contains(self) }
    /// Plays the frames in a direction (Aseprite's Animation Direction).
    var playsFrames: Bool { self == .gif || self == .pngSequence }
    /// An image, so layers, scale and pixel ratio apply; `.aseprite` is the sprite as is.
    var isImage: Bool { self != .aseprite }
}

/// Which frames an export takes (Aseprite's Frames field).
enum ExportFrames: Hashable {
    case all, current
    case tag(UUID)
    /// Frame indices, inclusive.
    case range(from: Int, to: Int)
}

/// The Export dialog's choices, as in Aseprite's Export As.
/// https://www.aseprite.org/docs/exporting/
struct ExportOptions: Hashable {
    var format = ExportFormat.png
    var frames = ExportFrames.all
    /// Just this layer; nil exports the visible layers.
    var layer: UUID?
    /// Whole multiples keep pixels sharp.
    var scale = 4
    /// nil plays the tag's direction (forward without a tag).
    var direction: AnimationDirection?
    /// Stretches pixels by the sprite's pixel ratio, as they show on the canvas.
    var applyPixelRatio = true
    /// Aseprite's Export for Twitter: GIF delays Twitter plays right, and PNGs it keeps as PNG.
    var forTwitter = false
    /// A sprite sheet comes with Aseprite's JSON data.
    var includeData = false
}

enum ExportError: LocalizedError {
    case encodingFailed

    var errorDescription: String? { L10n.string("Couldn't create the image.") }
}

enum Exporter {
    // MARK: What gets exported

    static func tag(_ sprite: Sprite, _ options: ExportOptions) -> FrameTag? {
        guard case .tag(let id) = options.frames else { return nil }
        return sprite.tags.first { $0.id == id }
    }

    /// The chosen frames in order.
    static func frames(_ sprite: Sprite, _ options: ExportOptions, current: Int) -> [Int] {
        let last = sprite.frames.count - 1
        switch options.frames {
        case .all: return Array(sprite.frames.indices)
        case .current: return [min(current, last)]
        case .tag: return tag(sprite, options).map { Array($0.from...min($0.to, last)) } ?? Array(sprite.frames.indices)
        case .range(let from, let to):
            let a = max(0, min(from, last)), b = max(0, min(to, last))
            return Array(min(a, b)...max(a, b))
        }
    }

    /// The frames as they play, in the chosen direction, and how many times
    /// the animation loops (0 = forever).
    static func playback(_ sprite: Sprite, _ options: ExportOptions, current: Int) -> (frames: [Int], loopCount: Int) {
        let base = frames(sprite, options, current: current)
        let tag = tag(sprite, options)
        guard let first = base.first, let last = base.last, first < last else { return (base, 0) }
        let direction = options.direction ?? tag?.direction ?? .forward
        return (Playback.cycle(from: first, to: last, direction: direction), tag?.repeatCount ?? 0)
    }

    /// Frames a GIF plays and how many times it loops (0 = forever):
    /// the tag's cycle, honouring its direction, or every frame in order.
    static func animation(_ sprite: Sprite, tag: FrameTag?) -> (frames: [Int], loopCount: Int) {
        guard let tag else { return (Array(sprite.frames.indices), 0) }
        return (Playback.cycle(from: tag.from, to: tag.to, direction: tag.direction), tag.repeatCount)
    }

    /// The sprite with only `layer` showing (and the groups it's in), or as it is.
    static func isolating(_ sprite: Sprite, layer: UUID?) -> Sprite {
        guard let layer, let target = sprite.layers.first(where: { $0.id == layer }) else { return sprite }
        let keep = Set([layer] + sprite.ancestors(of: target).map(\.id))
        var copy = sprite
        for i in copy.layers.indices { copy.layers[i].isVisible = keep.contains(copy.layers[i].id) }
        return copy
    }

    /// Output pixels per sprite pixel across and down.
    static func scales(_ sprite: Sprite, _ options: ExportOptions) -> (x: Int, y: Int) {
        let ratio = options.applyPixelRatio ? sprite.pixelRatio : .square
        return (options.scale * ratio.width, options.scale * ratio.height)
    }

    // MARK: Images

    /// Frames side by side, left to right. `frames` defaults to all of them.
    static func spriteSheet(_ sprite: Sprite, frames: [Int]? = nil) -> PixelImage {
        let frames = frames ?? Array(sprite.frames.indices)
        var sheet = PixelImage(width: sprite.width * frames.count, height: sprite.height)
        for (column, index) in frames.enumerated() {
            sheet.paste(sprite.composite(frameIndex: index), at: column * sprite.width, 0)
        }
        return sheet
    }

    /// With `forTwitter`, a fully opaque image gets one pixel at alpha 254,
    /// as Aseprite does, so Twitter keeps it a PNG instead of making it a JPEG.
    static func pngData(_ image: PixelImage, forTwitter: Bool = false) throws -> Data {
        var image = image
        if forTwitter, !image.pixels.isEmpty, image.pixels.allSatisfy({ $0.a == 255 }) {
            image.pixels[image.pixels.count - 1].a = 254
        }
        guard let cgImage = image.makeCGImage() else { throw ExportError.encodingFailed }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw ExportError.encodingFailed
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.encodingFailed }
        return data as Data
    }

    /// With `forTwitter`, as Aseprite's Export for Twitter: every delay at least
    /// 2/100 s and the last frame a quarter of its duration, which Twitter's
    /// conversion to video needs to play the animation right.
    static func gifData(_ sprite: Sprite, frames: [Int]? = nil, loopCount: Int = 0, scale: Int, scaleY: Int? = nil, forTwitter: Bool = false) throws -> Data {
        let frames = frames ?? Array(sprite.frames.indices)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames.count, nil) else {
            throw ExportError.encodingFailed
        }
        let fileProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loopCount]] as CFDictionary
        CGImageDestinationSetProperties(destination, fileProperties)
        for (position, index) in frames.enumerated() {
            guard let cgImage = sprite.composite(frameIndex: index).scaled(x: scale, y: scaleY ?? scale).makeCGImage() else {
                throw ExportError.encodingFailed
            }
            var centiseconds = Int((Double(sprite.frames[index].duration) / 10).rounded())
            if forTwitter {
                if position == frames.count - 1 { centiseconds /= 4 }
                centiseconds = max(2, centiseconds)
            }
            let delay = Double(centiseconds) / 100
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
    static func sheetData(_ sprite: Sprite, frames: [Int], scale: Int, scaleY: Int? = nil, imageName: String, baseName: String) throws -> Data {
        let sx = scale, sy = scaleY ?? scale
        let w = sprite.width * sx, h = sprite.height * sy
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
        let position = Dictionary(frames.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
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
                var entry: [String: Any] = ["frame": column, "bounds": rect(b.minX * sx, b.minY * sy, b.width * sx, b.height * sy)]
                if let c = key.center { entry["center"] = rect(c.minX * sx, c.minY * sy, c.width * sx, c.height * sy) }
                if let p = key.pivot { entry["pivot"] = ["x": p.x * sx, "y": p.y * sy] }
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

    // MARK: Files

    private static func safe(_ name: String) -> String {
        name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
    }

    /// Writes the export to temporary files ready to share: one image, one
    /// PNG per frame or per slice, a sprite sheet with its JSON data, or the
    /// `.aseprite` file.
    static func exportFiles(_ sprite: Sprite, name: String, frameIndex: Int, options: ExportOptions) throws -> [URL] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        // Files from earlier exports (a longer sequence, say) would be shared along.
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var base = safe(name)
        if base.isEmpty { base = "sprite" }
        if options.format.exportsFrames, let tag = tag(sprite, options) { base += "-\(safe(tag.name))" }
        func write(_ data: Data, _ file: String) throws -> URL {
            let url = directory.appendingPathComponent(file)
            try data.write(to: url, options: .atomic)
            return url
        }

        let source = isolating(sprite, layer: options.layer)
        let (sx, sy) = scales(sprite, options)
        switch options.format {
        case .png:
            return [try write(pngData(source.composite(frameIndex: frameIndex).scaled(x: sx, y: sy), forTwitter: options.forTwitter), "\(base).png")]
        case .pngSequence:
            // name_001.png, name_002.png… in the order they play.
            let frames = playback(sprite, options, current: frameIndex).frames
            let digits = max(3, String(frames.count).count)
            return try frames.enumerated().map { position, index in
                let number = String(repeating: "0", count: max(0, digits - String(position + 1).count)) + String(position + 1)
                return try write(pngData(source.composite(frameIndex: index).scaled(x: sx, y: sy), forTwitter: options.forTwitter), "\(base)_\(number).png")
            }
        case .gif:
            let animation = playback(sprite, options, current: frameIndex)
            return [try write(gifData(source, frames: animation.frames, loopCount: animation.loopCount, scale: sx, scaleY: sy, forTwitter: options.forTwitter), "\(base).gif")]
        case .spriteSheet:
            let frames = frames(sprite, options, current: frameIndex)
            let image = try write(pngData(spriteSheet(source, frames: frames).scaled(x: sx, y: sy)), "\(base)-sheet.png")
            guard options.includeData else { return [image] }
            let json = try sheetData(source, frames: frames, scale: sx, scaleY: sy, imageName: image.lastPathComponent, baseName: base)
            return [image, try write(json, "\(base)-sheet.json")]
        case .slices:
            var used: Set<String> = []
            return try sliceImages(source, frameIndex: frameIndex).map { slice in
                var file = safe("\(base)-\(slice.name)")
                while used.contains(file) { file += "-2" }
                used.insert(file)
                return try write(pngData(slice.image.scaled(x: sx, y: sy), forTwitter: options.forTwitter), "\(file).png")
            }
        case .aseprite:
            return [try write(AsepriteFile.write(sprite), "\(base).aseprite")]
        }
    }
}

extension PixelImage {
    /// Nearest-neighbour scaling by whole factors, which may differ across and down.
    func scaled(x sx: Int, y sy: Int) -> PixelImage {
        guard sx != 1 || sy != 1 else { return self }
        guard sx == sy else {
            var out = PixelImage(width: width * sx, height: height * sy)
            for y in 0..<out.height {
                for x in 0..<out.width { out[x, y] = self[x / sx, y / sy] }
            }
            return out
        }
        return scaled(by: sx)
    }
}
