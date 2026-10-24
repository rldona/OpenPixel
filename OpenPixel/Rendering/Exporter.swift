import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case png, spriteSheet, gif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png: "PNG"
        case .spriteSheet: "Hoja de sprites"
        case .gif: "GIF animado"
        }
    }

    var subtitle: String {
        switch self {
        case .png: "Frame actual"
        case .spriteSheet: "Todos los frames en fila"
        case .gif: "Con la duración de cada frame"
        }
    }

    var fileExtension: String { self == .gif ? "gif" : "png" }
}

enum ExportError: LocalizedError {
    case encodingFailed

    var errorDescription: String? { "No se pudo generar la imagen." }
}

enum Exporter {
    /// Frames side by side, left to right.
    static func spriteSheet(_ sprite: Sprite) -> PixelImage {
        var sheet = PixelImage(width: sprite.width * sprite.frames.count, height: sprite.height)
        for index in sprite.frames.indices {
            sheet.paste(sprite.composite(frameIndex: index), at: index * sprite.width, 0)
        }
        return sheet
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

    static func gifData(_ sprite: Sprite, scale: Int) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, sprite.frames.count, nil) else {
            throw ExportError.encodingFailed
        }
        let fileProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary
        CGImageDestinationSetProperties(destination, fileProperties)
        for (index, frame) in sprite.frames.enumerated() {
            guard let cgImage = sprite.composite(frameIndex: index).scaled(by: scale).makeCGImage() else {
                throw ExportError.encodingFailed
            }
            let delay = Double(frame.duration) / 1000
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
    static func export(_ sprite: Sprite, name: String, frameIndex: Int, format: ExportFormat, scale: Int) throws -> URL {
        let data: Data
        switch format {
        case .png:
            data = try pngData(sprite.composite(frameIndex: frameIndex).scaled(by: scale))
        case .spriteSheet:
            data = try pngData(spriteSheet(sprite).scaled(by: scale))
        case .gif:
            data = try gifData(sprite, scale: scale)
        }
        let safeName = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
        let suffix = format == .spriteSheet ? "-sheet" : ""
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Export", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(safeName.isEmpty ? "sprite" : safeName)\(suffix).\(format.fileExtension)")
        try data.write(to: url, options: .atomic)
        return url
    }
}
