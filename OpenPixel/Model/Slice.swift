import Foundation

extension PixelRect: Codable {
    private enum CodingKeys: String, CodingKey { case x, y, w, h }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let x = try c.decode(Int.self, forKey: .x), y = try c.decode(Int.self, forKey: .y)
        self.init(minX: x, minY: y, maxX: x + (try c.decode(Int.self, forKey: .w)) - 1, maxY: y + (try c.decode(Int.self, forKey: .h)) - 1)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(minX, forKey: .x)
        try c.encode(minY, forKey: .y)
        try c.encode(width, forKey: .w)
        try c.encode(height, forKey: .h)
    }
}

extension PixelPoint: Codable {
    private enum CodingKeys: String, CodingKey { case x, y }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(x: try c.decode(Int.self, forKey: .x), y: try c.decode(Int.self, forKey: .y))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(x, forKey: .x)
        try c.encode(y, forKey: .y)
    }
}

/// Aseprite's slices: named rectangles of the sprite, with an optional
/// 9-slice centre and pivot, used by games for UI pieces, hitboxes and
/// anchors. https://www.aseprite.org/docs/slices/
struct Slice: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var color: PixelColor
    /// The slice from a frame onward: each key applies until the next one.
    var keys: [SliceKey]

    /// The key in effect at `frameIndex`, given the sprite's frame order.
    func key(at frameIndex: Int, frames: [Frame]) -> SliceKey? {
        let order = Dictionary(uniqueKeysWithValues: frames.enumerated().map { ($1.id, $0) })
        return keys
            .compactMap { key in order[key.frame].map { (index: $0, key: key) } }
            .filter { $0.index <= frameIndex }
            .max { $0.index < $1.index }?.key
            // Before the first key, the first one applies.
            ?? keys.compactMap { key in order[key.frame].map { (index: $0, key: key) } }.min { $0.index < $1.index }?.key
    }

    /// Colors given to new slices in turn, like Aseprite's default blue and its neighbours.
    static let colors = [
        PixelColor(r: 0, g: 0, b: 255), PixelColor(r: 255, g: 0, b: 128), PixelColor(r: 0, g: 170, b: 85),
        PixelColor(r: 255, g: 128, b: 0), PixelColor(r: 128, g: 0, b: 255)
    ]
}

struct SliceKey: Codable, Equatable, Sendable {
    /// The frame this key starts at.
    var frame: UUID
    var bounds: PixelRect
    /// 9-slice centre, relative to `bounds`' top-left corner.
    var center: PixelRect?
    /// Pivot, relative to `bounds`' top-left corner.
    var pivot: PixelPoint?
}

extension Sprite {
    /// Keys on frames that were deleted go away; a slice left without keys
    /// keeps its last shape from the first frame.
    mutating func normalizeSlices() {
        guard !slices.isEmpty, let first = frames.first?.id else { return }
        let ids = Set(frames.map(\.id))
        for i in slices.indices {
            let kept = slices[i].keys.filter { ids.contains($0.frame) }
            if kept.isEmpty, var last = slices[i].keys.last {
                last.frame = first
                slices[i].keys = [last]
            } else if kept.count != slices[i].keys.count {
                slices[i].keys = kept
            }
        }
    }
}
