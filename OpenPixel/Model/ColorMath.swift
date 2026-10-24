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

/// Hue (0..<360), saturation and lightness (0...1).
struct HSL: Equatable, Sendable {
    var h: Double
    var s: Double
    var l: Double
}

extension PixelColor {
    var hsl: HSL {
        let r = Double(r) / 255, g = Double(g) / 255, b = Double(b) / 255
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        let l = (maxC + minC) / 2
        let s = delta == 0 ? 0 : delta / (1 - abs(2 * l - 1))
        return HSL(h: hsv.h, s: min(1, s), l: l)
    }

    init(hsl: HSL, alpha: UInt8 = 255) {
        let s = min(1, max(0, hsl.s)), l = min(1, max(0, hsl.l))
        // HSL to HSV, then the HSV conversion.
        let v = l + s * min(l, 1 - l)
        self.init(hsv: HSV(h: hsl.h, s: v == 0 ? 0 : 2 * (1 - l / v), v: v), alpha: alpha)
    }
}

/// Aseprite's Edit > Adjustments > Hue/Saturation, with its four modes.
/// https://www.aseprite.org/docs/hue-saturation/
struct HueSaturation: Hashable, Sendable {
    enum Mode: String, CaseIterable, Identifiable, Sendable {
        /// Saturation and value or lightness scale with the slider (HSV, HSL);
        /// the "+" modes add to them instead.
        case hsv, hsl, hsvAdd, hslAdd
        var id: String { rawValue }

        var title: String {
            switch self {
            case .hsv: "HSV"
            case .hsl: "HSL"
            case .hsvAdd: "HSV+"
            case .hslAdd: "HSL+"
            }
        }

        var usesLightness: Bool { self == .hsl || self == .hslAdd }
    }

    var mode = Mode.hsl
    /// Degrees, -180...180.
    var hue = 0.0
    /// -1...1, from the sliders' -100...100.
    var saturation = 0.0
    var lightness = 0.0
    var alpha = 0.0
    /// The channels that change (Aseprite's R G B A buttons).
    var red = true, green = true, blue = true, alphaChannel = true

    var isIdentity: Bool { hue == 0 && saturation == 0 && lightness == 0 && alpha == 0 }

    /// The same math as Aseprite's filter.
    func apply(_ c: PixelColor) -> PixelColor {
        guard c.a != 0 else { return c }
        let multiply = mode == .hsv || mode == .hsl
        func adjust(_ value: Double, _ amount: Double) -> Double {
            min(1, max(0, multiply ? value * (1 + amount) : value + amount))
        }
        var h = (mode.usesLightness ? c.hsl.h : c.hsv.h) + hue
        while h < 0 { h += 360 }
        h = h.truncatingRemainder(dividingBy: 360)
        let rgb: PixelColor
        if mode.usesLightness {
            let hsl = c.hsl
            rgb = PixelColor(hsl: HSL(h: h, s: adjust(hsl.s, saturation), l: adjust(hsl.l, lightness)))
        } else {
            let hsv = c.hsv
            rgb = PixelColor(hsv: HSV(h: h, s: adjust(hsv.s, saturation), v: adjust(hsv.v, lightness)))
        }
        var out = c
        if red { out.r = rgb.r }
        if green { out.g = rgb.g }
        if blue { out.b = rgb.b }
        if alphaChannel { out.a = UInt8(min(255, max(0, (Double(c.a) * (1 + alpha)).rounded(.towardZero)))) }
        return out.a == 0 ? .clear : out
    }
}

/// Ramps around a base color, like the Color Shading extension for Aseprite:
/// shades that shift hue as they get darker or lighter, plain lightness,
/// saturation and hue steps. Seven colors each, the base in the middle.
enum ColorShading {
    static let steps = [-3, -2, -1, 0, 1, 2, 3]

    /// Darker towards a cool blue, lighter towards a warm yellow, as painters shade.
    static func shades(_ base: PixelColor) -> [PixelColor] {
        let hsv = base.hsv
        return steps.map { step in
            guard step != 0 else { return base }
            let t = Double(abs(step)) / 3
            let target = step < 0 ? 240.0 : 60.0
            let h = rotate(hsv.h, towards: target, by: 24 * t)
            let s = step < 0 ? hsv.s + (1 - hsv.s) * 0.15 * t : hsv.s * (1 - 0.35 * t)
            let v = step < 0 ? hsv.v * (1 - 0.6 * t) : hsv.v + (1 - hsv.v) * 0.7 * t
            return PixelColor(hsv: HSV(h: h, s: s, v: v), alpha: base.a)
        }
    }

    static func lights(_ base: PixelColor) -> [PixelColor] {
        let hsl = base.hsl
        return steps.map { step in
            guard step != 0 else { return base }
            let t = Double(abs(step)) / 4
            return PixelColor(hsl: HSL(h: hsl.h, s: hsl.s, l: step < 0 ? hsl.l * (1 - t) : hsl.l + (1 - hsl.l) * t), alpha: base.a)
        }
    }

    static func saturations(_ base: PixelColor) -> [PixelColor] {
        let hsv = base.hsv
        return steps.map { step in
            guard step != 0 else { return base }
            let t = Double(abs(step)) / 3
            return PixelColor(hsv: HSV(h: hsv.h, s: step < 0 ? hsv.s * (1 - t) : hsv.s + (1 - hsv.s) * t, v: hsv.v), alpha: base.a)
        }
    }

    static func hues(_ base: PixelColor) -> [PixelColor] {
        let hsv = base.hsv
        return steps.map { step in
            step == 0 ? base : PixelColor(hsv: HSV(h: hsv.h + Double(step) * 15, s: hsv.s, v: hsv.v), alpha: base.a)
        }
    }

    /// `hue` turned by up to `degrees` along the shorter way to `target`.
    static func rotate(_ hue: Double, towards target: Double, by degrees: Double) -> Double {
        var delta = (target - hue).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        let step = abs(delta) < degrees ? delta : (delta < 0 ? -degrees : degrees)
        return (hue + step + 360).truncatingRemainder(dividingBy: 360)
    }
}
