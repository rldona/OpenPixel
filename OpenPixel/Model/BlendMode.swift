import SwiftUI

/// How a layer's pixels combine with the layers under it (Aseprite's layer
/// blend modes). The blend gives the color; the layer's alpha and opacity
/// still decide how much of it shows, as in the W3C compositing spec.
enum BlendMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case normal, multiply, screen, overlay, darken, lighten
    case colorDodge, colorBurn, hardLight, softLight
    case difference, exclusion, addition, subtract, divide

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .normal: "Normal"
        case .multiply: "Multiply"
        case .screen: "Screen"
        case .overlay: "Overlay"
        case .darken: "Darken"
        case .lighten: "Lighten"
        case .colorDodge: "Color dodge"
        case .colorBurn: "Color burn"
        case .hardLight: "Hard light"
        case .softLight: "Soft light"
        case .difference: "Difference"
        case .exclusion: "Exclusion"
        case .addition: "Addition"
        case .subtract: "Subtract"
        case .divide: "Divide"
        }
    }

    /// The blended value of one channel, both in 0...1 (b: backdrop, s: source).
    func channel(_ b: Double, _ s: Double) -> Double {
        switch self {
        case .normal: return s
        case .multiply: return b * s
        case .screen: return b + s - b * s
        case .overlay: return BlendMode.hardLight.channel(s, b)
        case .darken: return min(b, s)
        case .lighten: return max(b, s)
        case .colorDodge:
            if b == 0 { return 0 }
            return s >= 1 ? 1 : min(1, b / (1 - s))
        case .colorBurn:
            if b >= 1 { return 1 }
            return s <= 0 ? 0 : 1 - min(1, (1 - b) / s)
        case .hardLight:
            return s <= 0.5 ? b * 2 * s : BlendMode.screen.channel(b, 2 * s - 1)
        case .softLight:
            if s <= 0.5 { return b - (1 - 2 * s) * b * (1 - b) }
            let d = b <= 0.25 ? ((16 * b - 12) * b + 4) * b : b.squareRoot()
            return b + (2 * s - 1) * (d - b)
        case .difference: return abs(b - s)
        case .exclusion: return b + s - 2 * b * s
        case .addition: return min(1, b + s)
        case .subtract: return max(0, b - s)
        case .divide: return s <= 0 ? 1 : min(1, b / s)
        }
    }

    /// `src` composited over `dst` with this mode and `opacity`.
    func composite(_ src: PixelColor, over dst: PixelColor, opacity: Double) -> PixelColor {
        guard self != .normal, dst.a != 0 else { return src.blended(over: dst, opacity: opacity) }
        let ab = Double(dst.a) / 255
        func mix(_ s: UInt8, _ b: UInt8) -> UInt8 {
            let cs = Double(s) / 255, cb = Double(b) / 255
            // Where the backdrop is transparent the source shows as it is.
            let c = (1 - ab) * cs + ab * channel(cb, cs)
            return UInt8((min(1, max(0, c)) * 255).rounded())
        }
        let blended = PixelColor(r: mix(src.r, dst.r), g: mix(src.g, dst.g), b: mix(src.b, dst.b), a: src.a)
        return blended.blended(over: dst, opacity: opacity)
    }
}
