import Foundation

/// Hue (0..<360), saturation and value (0...1), as in Aseprite's HSB sliders.
struct HSV: Equatable, Sendable {
    var h: Double
    var s: Double
    var v: Double
}

extension PixelColor {
    var hsv: HSV {
        let r = Double(r) / 255, g = Double(g) / 255, b = Double(b) / 255
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        var h = 0.0
        if delta > 0 {
            if maxC == r { h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == g { h = 60 * ((b - r) / delta + 2) }
            else { h = 60 * ((r - g) / delta + 4) }
        }
        if h < 0 { h += 360 }
        return HSV(h: h, s: maxC == 0 ? 0 : delta / maxC, v: maxC)
    }

    init(hsv: HSV, alpha: UInt8 = 255) {
        let h = (hsv.h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let s = min(1, max(0, hsv.s)), v = min(1, max(0, hsv.v))
        let c = v * s, x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1)), m = v - c
        let (r, g, b): (Double, Double, Double) = switch Int(h / 60) {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        func byte(_ v: Double) -> UInt8 { UInt8(min(255, max(0, ((v + m) * 255).rounded()))) }
        self.init(r: byte(r), g: byte(g), b: byte(b), a: alpha)
    }

    /// Perceived brightness, 0...1 (Rec. 709).
    var luminance: Double {
        (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255
    }

    /// Straight interpolation towards `other`, alpha included.
    func mixed(with other: PixelColor, _ t: Double) -> PixelColor {
        func lerp(_ a: UInt8, _ b: UInt8) -> UInt8 { UInt8((Double(a) + (Double(b) - Double(a)) * t).rounded()) }
        return PixelColor(r: lerp(r, other.r), g: lerp(g, other.g), b: lerp(b, other.b), a: lerp(a, other.a))
    }

    /// Whether every channel is within `tolerance` (0...255) of `other`, like
    /// Aseprite's Replace Color. Fully transparent pixels match each other whatever their RGB.
    func matches(_ other: PixelColor, tolerance: Int) -> Bool {
        if a == 0 && other.a == 0 { return true }
        func close(_ x: UInt8, _ y: UInt8) -> Bool { abs(Int(x) - Int(y)) <= tolerance }
        return close(r, other.r) && close(g, other.g) && close(b, other.b) && close(a, other.a)
    }
}

/// Colors that go well with a base color, by rotating its hue.
enum ColorHarmony: String, CaseIterable, Identifiable, Sendable {
    case complementary, analogous, triadic, splitComplementary, tetradic

    var id: String { rawValue }

    /// Hue offsets from the base color, which comes first.
    var offsets: [Double] {
        switch self {
        case .complementary: [0, 180]
        case .analogous: [-30, 0, 30]
        case .triadic: [0, 120, 240]
        case .splitComplementary: [0, 150, 210]
        case .tetradic: [0, 90, 180, 270]
        }
    }

    func colors(for base: PixelColor) -> [PixelColor] {
        let hsv = base.hsv
        return offsets.map { PixelColor(hsv: HSV(h: hsv.h + $0, s: hsv.s, v: hsv.v), alpha: base.a) }
    }
}

extension PixelColor {
    /// Darker to lighter versions of the color (shades, the color, tints), for quick ramps.
    var shadesAndTints: [PixelColor] {
        let black = PixelColor(r: 0, g: 0, b: 0, a: a), white = PixelColor(r: 255, g: 255, b: 255, a: a)
        return [0.75, 0.5, 0.25].map { mixed(with: black, $0) } + [self] + [0.25, 0.5, 0.75].map { mixed(with: white, $0) }
    }
}
