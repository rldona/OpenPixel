import Foundation

/// Aseprite's symmetry: what you draw is repeated mirrored across a vertical
/// axis (horizontal symmetry), a horizontal axis (vertical symmetry) or both.
/// https://www.aseprite.org/docs/symmetry/
struct Symmetry: Equatable {
    /// The rail button turns symmetry on and off without forgetting the axes chosen.
    var isEnabled = false
    var horizontal = true
    var vertical = false
    /// Axis positions in half pixels from the left and top edges, so an axis
    /// can run between two pixels or through the middle of one. nil is the centre.
    var axisX2: Int?
    var axisY2: Int?

    var isOn: Bool { isEnabled && (horizontal || vertical) }

    func axisX2(width: Int) -> Int { min(2 * width - 1, max(1, axisX2 ?? width)) }
    func axisY2(height: Int) -> Int { min(2 * height - 1, max(1, axisY2 ?? height)) }

    /// The mirrored copies of `p` (not `p` itself).
    func images(of p: PixelPoint, width: Int, height: Int) -> [PixelPoint] {
        guard isOn else { return [] }
        let mx = axisX2(width: width) - 1 - p.x, my = axisY2(height: height) - 1 - p.y
        switch (horizontal, vertical) {
        case (true, true): return [PixelPoint(x: mx, y: p.y), PixelPoint(x: p.x, y: my), PixelPoint(x: mx, y: my)]
        case (true, false): return [PixelPoint(x: mx, y: p.y)]
        case (false, true): return [PixelPoint(x: p.x, y: my)]
        default: return []
        }
    }

    /// `rect` plus its mirrored copies.
    func covering(_ rect: PixelRect, width: Int, height: Int) -> PixelRect {
        guard isOn else { return rect }
        var result = rect
        for corner in images(of: PixelPoint(x: rect.minX, y: rect.minY), width: width, height: height)
            + images(of: PixelPoint(x: rect.maxX, y: rect.maxY), width: width, height: height) {
            result = result.union(PixelRect(minX: corner.x, minY: corner.y, maxX: corner.x, maxY: corner.y))
        }
        return result
    }
}
