import Foundation

/// Follows Aseprite's model: a sprite has layers and frames, and the image
/// at a given layer × frame intersection is a cel.
/// https://www.aseprite.org/docs/basics/

enum ColorMode: String, Codable, Sendable {
    case rgba
}

/// The image of a reference layer: kept at its own resolution (not turned
/// into sprite pixels) and placed over the canvas in sprite coordinates.
struct ReferenceImage: Codable, Equatable, Sendable {
    /// PNG or JPEG data, as imported.
    var data: Data
    /// Where it sits, in sprite pixels (fractions allowed).
    var frame: CGRect
}

struct Layer: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var isVisible = true
    var isLocked = false
    var opacity: Double = 1
    /// New frames link this layer's cel instead of copying it (Aseprite's continuous layers).
    var isContinuous = false
    /// Aseprite's background layer: opaque, always at the bottom, erased to the
    /// secondary color. https://www.aseprite.org/docs/layers/#background-layer
    var isBackground = false
    /// Aseprite's reference layer: an image to trace over. It can't be drawn
    /// on, isn't exported and is shown at its own resolution.
    var reference: ReferenceImage?
    var isReference: Bool { reference != nil }

    init(id: UUID = UUID(), name: String, isVisible: Bool = true, isLocked: Bool = false, opacity: Double = 1, isContinuous: Bool = false, isBackground: Bool = false, reference: ReferenceImage? = nil) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.opacity = opacity
        self.isContinuous = isContinuous
        self.isBackground = isBackground
        self.reference = reference
    }

    private enum CodingKeys: String, CodingKey { case id, name, isVisible, isLocked, opacity, isContinuous, isBackground, reference }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        isVisible = try c.decode(Bool.self, forKey: .isVisible)
        isLocked = try c.decode(Bool.self, forKey: .isLocked)
        opacity = try c.decode(Double.self, forKey: .opacity)
        isContinuous = try c.decodeIfPresent(Bool.self, forKey: .isContinuous) ?? false
        isBackground = try c.decodeIfPresent(Bool.self, forKey: .isBackground) ?? false
        reference = try c.decodeIfPresent(ReferenceImage.self, forKey: .reference)
    }
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
    var tags: [FrameTag] = []
    /// Linked cels: cels with the same group share one image, and editing
    /// one changes all of them. https://www.aseprite.org/docs/linked-cels/
    var links: [CelKey: UUID] = [:]
    /// Per-cel opacity on top of the layer's (Aseprite's Cel Properties). Missing keys are 1.
    var celOpacity: [CelKey: Double] = [:]

    static func blank(width: Int, height: Int, background: PixelColor?, palette: [PixelColor]) -> Sprite {
        let frame = Frame()
        let layer = Layer(name: background == nil ? L10n.string("Layer %d", 1) : L10n.string("Background"), isBackground: background != nil)
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
        var pixels = [PixelColor](repeating: .clear, count: width * height)
        composite(frameIndex: frameIndex, into: &pixels, rect: .full(width: width, height: height))
        return PixelImage(width: width, height: height, pixels: pixels)
    }

    /// Recomposites only `rect` of a frame into an existing `width × height` buffer.
    /// This is the per-stroke hot path, so it works on raw buffers.
    func composite(frameIndex: Int, into out: inout [PixelColor], rect: PixelRect) {
        precondition(out.count == width * height, "Buffer does not match sprite size")
        let w = width
        out.withUnsafeMutableBufferPointer { dst in
            for y in rect.minY...rect.maxY {
                for x in rect.minX...rect.maxX { dst[y * w + x] = .clear }
            }
            guard frames.indices.contains(frameIndex) else { return }
            let frameID = frames[frameIndex].id
            // Reference layers aren't part of the image: the canvas shows them on its own.
            for layer in layers where layer.isVisible && layer.opacity > 0 && !layer.isReference {
                let key = CelKey(layer: layer.id, frame: frameID)
                guard let image = cels[key] else { continue }
                let opacity = layer.opacity * (celOpacity[key] ?? 1)
                guard opacity > 0 else { continue }
                let opaqueLayer = opacity >= 1
                image.pixels.withUnsafeBufferPointer { src in
                    for y in rect.minY...rect.maxY {
                        var i = y * w + rect.minX
                        for _ in rect.minX...rect.maxX {
                            let s = src[i]
                            if s.a == 255 && opaqueLayer {
                                dst[i] = s
                            } else if s.a != 0 {
                                dst[i] = s.blended(over: dst[i], opacity: opacity)
                            }
                            i += 1
                        }
                    }
                }
            }
        }
    }

    var totalDuration: Int { frames.reduce(0) { $0 + $1.duration } }

    /// A sprite has at most one background layer, and it stays at the bottom.
    mutating func keepBackgroundAtBottom() {
        guard let index = layers.firstIndex(where: \.isBackground), index > 0 else { return }
        layers.insert(layers.remove(at: index), at: 0)
    }

    // MARK: Linked cels

    func isLinked(_ key: CelKey) -> Bool { links[key] != nil }

    /// Copies `key`'s image and opacity to every cel linked with it. Images
    /// are copy-on-write, so linked cels share storage until one is edited.
    mutating func syncLinks(from key: CelKey) {
        guard let group = links[key] else { return }
        let image = cels[key], opacity = celOpacity[key]
        for (other, g) in links where g == group && other != key {
            cels[other] = image
            celOpacity[other] = opacity
        }
    }

    /// Links `keys` into one group sharing the image of the first key.
    mutating func link(_ keys: [CelKey]) {
        guard let first = keys.first, keys.count > 1 else { return }
        let group = links[first] ?? UUID()
        for key in keys {
            links[key] = group
            cels[key] = cels[first]
            celOpacity[key] = celOpacity[first]
        }
        normalizeLinks()
    }

    mutating func unlink(_ keys: [CelKey]) {
        for key in keys { links[key] = nil }
        normalizeLinks()
    }

    /// Drops links and cel opacities of deleted layers, frames or cels, and
    /// link groups left with one cel.
    mutating func normalizeLinks() {
        if !celOpacity.isEmpty { celOpacity = celOpacity.filter { cels[$0.key] != nil && $0.value < 1 } }
        guard !links.isEmpty else { return }
        let layerIDs = Set(layers.map(\.id)), frameIDs = Set(frames.map(\.id))
        links = links.filter { layerIDs.contains($0.key.layer) && frameIDs.contains($0.key.frame) }
        var counts: [UUID: Int] = [:]
        for g in links.values { counts[g, default: 0] += 1 }
        links = links.filter { counts[$0.value, default: 0] > 1 }
    }
}

extension Sprite: Codable {
    private struct Cel: Codable {
        var layer: UUID
        var frame: UUID
        var image: PixelImage
    }

    private struct Link: Codable {
        var layer: UUID
        var frame: UUID
        var group: UUID
    }

    private struct CelOpacity: Codable {
        var layer: UUID
        var frame: UUID
        var opacity: Double
    }

    private enum CodingKeys: String, CodingKey { case width, height, colorMode, layers, frames, cels, palette, tags, links, celOpacity }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        colorMode = try c.decodeIfPresent(ColorMode.self, forKey: .colorMode) ?? .rgba
        layers = try c.decode([Layer].self, forKey: .layers)
        frames = try c.decode([Frame].self, forKey: .frames)
        palette = try c.decode([PixelColor].self, forKey: .palette)
        tags = try c.decodeIfPresent([FrameTag].self, forKey: .tags) ?? []
        let linkList = try c.decodeIfPresent([Link].self, forKey: .links) ?? []
        links = Dictionary(linkList.map { (CelKey(layer: $0.layer, frame: $0.frame), $0.group) }, uniquingKeysWith: { a, _ in a })
        let opacityList = try c.decodeIfPresent([CelOpacity].self, forKey: .celOpacity) ?? []
        celOpacity = Dictionary(opacityList.map { (CelKey(layer: $0.layer, frame: $0.frame), $0.opacity) }, uniquingKeysWith: { a, _ in a })
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
        try c.encode(tags, forKey: .tags)
        let linkList = links.map { Link(layer: $0.key.layer, frame: $0.key.frame, group: $0.value) }
            .sorted { ($0.layer.uuidString, $0.frame.uuidString) < ($1.layer.uuidString, $1.frame.uuidString) }
        try c.encode(linkList, forKey: .links)
        let opacityList = celOpacity.map { CelOpacity(layer: $0.key.layer, frame: $0.key.frame, opacity: $0.value) }
            .sorted { ($0.layer.uuidString, $0.frame.uuidString) < ($1.layer.uuidString, $1.frame.uuidString) }
        try c.encode(opacityList, forKey: .celOpacity)
        let list = cels.map { Cel(layer: $0.key.layer, frame: $0.key.frame, image: $0.value) }
            .sorted { ($0.layer.uuidString, $0.frame.uuidString) < ($1.layer.uuidString, $1.frame.uuidString) }
        try c.encode(list, forKey: .cels)
    }
}

/// What is written to disk: one `.openpixel` JSON file per sprite.
struct SpriteFile: Codable, Sendable {
    var version = 1
    var name: String
    var sprite: Sprite
}
