import Foundation

/// Follows Aseprite's model: a sprite has layers and frames, and the image
/// at a given layer × frame intersection is a cel.
/// https://www.aseprite.org/docs/basics/

enum ColorMode: String, Codable, Sendable {
    case rgba
}

struct Layer: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var isVisible = true
    var isLocked = false
    var opacity: Double = 1
}

struct Frame: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    /// Duration in milliseconds.
    var duration: Int = 100
}

struct CelKey: Hashable, Codable, Sendable {
    var layer: UUID
    var frame: UUID
}

struct Sprite: Equatable, Sendable {
    var width: Int
    var height: Int
    var colorMode: ColorMode = .rgba
    /// Ordered bottom to top.
    var layers: [Layer]
    var frames: [Frame]
    /// Missing keys are empty cels.
    var cels: [CelKey: PixelImage]
    var palette: [PixelColor]

    static func blank(width: Int, height: Int, background: PixelColor?, palette: [PixelColor]) -> Sprite {
        let frame = Frame()
        let layer = Layer(name: background == nil ? "Capa 1" : "Fondo")
        var cels: [CelKey: PixelImage] = [:]
        if let background {
            cels[CelKey(layer: layer.id, frame: frame.id)] = PixelImage(width: width, height: height, fill: background)
        }
        return Sprite(width: width, height: height, layers: [layer], frames: [frame], cels: cels, palette: palette)
    }

    func cel(layer: UUID, frame: UUID) -> PixelImage? {
        cels[CelKey(layer: layer, frame: frame)]
    }

    /// Flattens the visible layers of a frame.
    func composite(frameIndex: Int) -> PixelImage {
        var out = PixelImage(width: width, height: height)
        guard frames.indices.contains(frameIndex) else { return out }
        let frameID = frames[frameIndex].id
        for layer in layers where layer.isVisible && layer.opacity > 0 {
            guard let image = cel(layer: layer.id, frame: frameID) else { continue }
            for i in out.pixels.indices where image.pixels[i].a != 0 {
                out.pixels[i] = image.pixels[i].blended(over: out.pixels[i], opacity: layer.opacity)
            }
        }
        return out
    }

    var totalDuration: Int { frames.reduce(0) { $0 + $1.duration } }
}

extension Sprite: Codable {
    private struct Cel: Codable {
        var layer: UUID
        var frame: UUID
        var image: PixelImage
    }

    private enum CodingKeys: String, CodingKey { case width, height, colorMode, layers, frames, cels, palette }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        colorMode = try c.decodeIfPresent(ColorMode.self, forKey: .colorMode) ?? .rgba
        layers = try c.decode([Layer].self, forKey: .layers)
        frames = try c.decode([Frame].self, forKey: .frames)
        palette = try c.decode([PixelColor].self, forKey: .palette)
        let list = try c.decode([Cel].self, forKey: .cels)
        cels = Dictionary(list.map { (CelKey(layer: $0.layer, frame: $0.frame), $0.image) }, uniquingKeysWith: { a, _ in a })
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(colorMode, forKey: .colorMode)
        try c.encode(layers, forKey: .layers)
        try c.encode(frames, forKey: .frames)
        try c.encode(palette, forKey: .palette)
        let list = cels.map { Cel(layer: $0.key.layer, frame: $0.key.frame, image: $0.value) }
            .sorted { ($0.layer.uuidString, $0.frame.uuidString) < ($1.layer.uuidString, $1.frame.uuidString) }
        try c.encode(list, forKey: .cels)
    }
}

/// What is written to disk: one `.openpixel` JSON file per sprite.
struct SpriteFile: Codable {
    var version = 1
    var name: String
    var sprite: Sprite
}
