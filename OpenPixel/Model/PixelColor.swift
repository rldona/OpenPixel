import SwiftUI
import UIKit

/// A non-premultiplied 8-bit RGBA color.
struct PixelColor: Hashable, Sendable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8

    static let clear = PixelColor(r: 0, g: 0, b: 0, a: 0)
    static let black = PixelColor(r: 0, g: 0, b: 0)
    static let white = PixelColor(r: 255, g: 255, b: 255)

    init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// Parses `#RRGGBB` or `#RRGGBBAA`.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt32(s, radix: 16) else { return nil }
        if s.count == 6 {
            self.init(r: UInt8(v >> 16 & 0xFF), g: UInt8(v >> 8 & 0xFF), b: UInt8(v & 0xFF))
        } else {
            self.init(r: UInt8(v >> 24 & 0xFF), g: UInt8(v >> 16 & 0xFF), b: UInt8(v >> 8 & 0xFF), a: UInt8(v & 0xFF))
        }
    }

    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v * 255).rounded()))) }
        self.init(r: byte(r), g: byte(g), b: byte(b), a: byte(a))
    }

    var hex: String {
        a == 255
            ? String(format: "#%02X%02X%02X", Int(r), Int(g), Int(b))
            : String(format: "#%02X%02X%02X%02X", Int(r), Int(g), Int(b), Int(a))
    }

    var isTransparent: Bool { a == 0 }

    var color: Color {
        Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }

    /// Source-over compositing of `self` on top of `dst`.
    func blended(over dst: PixelColor, opacity: Double = 1) -> PixelColor {
        let sa = Double(a) / 255 * opacity
        if sa >= 1 { return self }
        if sa <= 0 { return dst }
        let da = Double(dst.a) / 255
        let oa = sa + da * (1 - sa)
        func channel(_ s: UInt8, _ d: UInt8) -> UInt8 {
            UInt8(((Double(s) * sa + Double(d) * da * (1 - sa)) / oa).rounded())
        }
        return PixelColor(r: channel(r, dst.r), g: channel(g, dst.g), b: channel(b, dst.b), a: UInt8((oa * 255).rounded()))
    }
}

extension PixelColor: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let color = PixelColor(hex: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid color \(string)")
        }
        self = color
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hex)
    }
}
