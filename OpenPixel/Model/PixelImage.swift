import Foundation

struct PixelPoint: Hashable, Sendable {
    var x: Int
    var y: Int
}

/// A rectangular grid of pixels. Value type with copy-on-write storage,
/// so undo snapshots are cheap until a pixel actually changes.
struct PixelImage: Equatable, Sendable {
    let width: Int
    let height: Int
    var pixels: [PixelColor]

    init(width: Int, height: Int, fill: PixelColor = .clear) {
        self.width = width
        self.height = height
        self.pixels = Array(repeating: fill, count: width * height)
    }

    init(width: Int, height: Int, pixels: [PixelColor]) {
        precondition(pixels.count == width * height, "Pixel count does not match size")
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    func contains(_ p: PixelPoint) -> Bool {
        p.x >= 0 && p.y >= 0 && p.x < width && p.y < height
    }

    subscript(x: Int, y: Int) -> PixelColor {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    subscript(p: PixelPoint) -> PixelColor {
        get { self[p.x, p.y] }
        set { self[p.x, p.y] = newValue }
    }

    var isEmpty: Bool { !pixels.contains { $0.a != 0 } }

    /// Non-premultiplied RGBA bytes, row by row.
    var rgbaData: Data {
        var bytes = [UInt8](repeating: 0, count: pixels.count * 4)
        for (i, p) in pixels.enumerated() {
            bytes[i * 4] = p.r
            bytes[i * 4 + 1] = p.g
            bytes[i * 4 + 2] = p.b
            bytes[i * 4 + 3] = p.a
        }
        return Data(bytes)
    }

    init?(width: Int, height: Int, rgbaData data: Data) {
        guard width > 0, height > 0, data.count == width * height * 4 else { return nil }
        let bytes = [UInt8](data)
        var pixels = [PixelColor]()
        pixels.reserveCapacity(width * height)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            pixels.append(PixelColor(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2], a: bytes[i + 3]))
        }
        self.init(width: width, height: height, pixels: pixels)
    }

    /// Nearest-neighbour upscale by an integer factor.
    func scaled(by factor: Int) -> PixelImage {
        guard factor > 1 else { return self }
        var out = PixelImage(width: width * factor, height: height * factor)
        for y in 0..<out.height {
            for x in 0..<out.width {
                out[x, y] = self[x / factor, y / factor]
            }
        }
        return out
    }

    /// Mixes every visible pixel towards `tint`, keeping alpha.
    func tinted(_ tint: PixelColor, amount: Double = 0.6) -> PixelImage {
        var out = self
        for i in out.pixels.indices where out.pixels[i].a != 0 {
            let p = out.pixels[i]
            func mix(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8((Double(a) * (1 - amount) + Double(b) * amount).rounded()) }
            out.pixels[i] = PixelColor(r: mix(p.r, tint.r), g: mix(p.g, tint.g), b: mix(p.b, tint.b), a: p.a)
        }
        return out
    }

    /// Copies `image` into this one with its top-left corner at (`dx`, `dy`).
    mutating func paste(_ image: PixelImage, at dx: Int, _ dy: Int) {
        for y in 0..<image.height {
            for x in 0..<image.width where x + dx < width && y + dy < height {
                self[x + dx, y + dy] = image[x, y]
            }
        }
    }
}

extension PixelImage: Codable {
    private enum CodingKeys: String, CodingKey { case width, height, rgba }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let width = try c.decode(Int.self, forKey: .width)
        let height = try c.decode(Int.self, forKey: .height)
        let data = try c.decode(Data.self, forKey: .rgba)
        guard let image = PixelImage(width: width, height: height, rgbaData: data) else {
            throw DecodingError.dataCorruptedError(forKey: .rgba, in: c, debugDescription: "Pixel data does not match size")
        }
        self = image
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(rgbaData, forKey: .rgba)
    }
}
