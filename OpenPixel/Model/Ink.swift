import SwiftUI

/// How a tool's color combines with the pixels under it (Aseprite's inks).
enum Ink: String, CaseIterable, Identifiable {
    /// Paints the color; a transparent color erases.
    case simple
    /// Always blends over what's there; a transparent color does nothing.
    case alphaCompositing
    /// Replaces color and alpha, so a semi-transparent color makes the pixel semi-transparent.
    case copyColor
    /// Changes the color only where there's something drawn, keeping its alpha.
    case lockAlpha
    /// Moves drawn pixels one step along the palette.
    case shading

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .simple: "Simple"
        case .alphaCompositing: "Alpha compositing"
        case .copyColor: "Copy alpha + color"
        case .lockAlpha: "Lock alpha"
        case .shading: "Shading"
        }
    }

    var systemImage: String {
        switch self {
        case .simple: "paintbrush.pointed"
        case .alphaCompositing: "circle.lefthalf.filled"
        case .copyColor: "square.on.square"
        case .lockAlpha: "lock.square"
        case .shading: "circle.bottomhalf.filled"
        }
    }

    /// The pixel that results from painting `src` over `dst` with `alpha`
    /// (0...255, the tool's opacity and pressure). `shade` gives the next
    /// palette color for the shading ink, or nil when `dst` isn't in the ramp.
    func apply(_ src: PixelColor, over dst: PixelColor, alpha: UInt8, shade: (PixelColor) -> PixelColor? = { _ in nil }) -> PixelColor {
        let t = Double(alpha) / 255
        guard t > 0 else { return dst }
        switch self {
        case .simple:
            guard src.a == 0 else { return src.blended(over: dst, opacity: t) }
            var erased = dst
            erased.a = UInt8((Double(dst.a) * (1 - t)).rounded())
            return erased.a == 0 ? .clear : erased
        case .alphaCompositing:
            return src.blended(over: dst, opacity: t)
        case .copyColor:
            if dst.a == 0 {
                var c = src
                c.a = UInt8((Double(src.a) * t).rounded())
                return c.a == 0 ? .clear : c
            }
            return dst.mixed(with: src, t)
        case .lockAlpha:
            guard dst.a != 0 else { return dst }
            var opaque = dst
            opaque.a = 255
            var c = src.blended(over: opaque, opacity: t)
            c.a = dst.a
            return c
        case .shading:
            guard dst.a != 0, let next = shade(dst) else { return dst }
            var c = next
            c.a = dst.a
            return t >= 1 ? c : dst.mixed(with: c, t)
        }
    }
}

/// Which way the shading ink moves along the palette.
enum ShadeDirection: String, CaseIterable, Identifiable {
    case forward, backward
    var id: String { rawValue }

    /// The color next to `color` in `ramp`, staying put at either end.
    func step(_ color: PixelColor, in ramp: [PixelColor]) -> PixelColor? {
        var opaque = color
        opaque.a = 255
        guard let i = ramp.firstIndex(of: opaque) else { return nil }
        let j = self == .forward ? min(ramp.count - 1, i + 1) : max(0, i - 1)
        return ramp[j]
    }
}
