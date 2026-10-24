import Foundation
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case png, spriteSheet, gif

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .png: "PNG"
        case .spriteSheet: "Sprite sheet"
        case .gif: "Animated GIF"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .png: "Current frame"
        case .spriteSheet: "All frames in a row"
        case .gif: "With each frame's duration"
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
