import CoreGraphics
import Foundation

/// How free rotation resamples pixels.
/// https://www.aseprite.org/docs/rotate/
enum RotationAlgorithm: String, CaseIterable, Identifiable {
    /// Upscales 8× with Scale2x before rotating, so edges stay clean.
    case rotSprite
    /// Plain nearest-neighbour.
    case fast
    var id: String { rawValue }
}

/// Position, size, rotation and pivot of floating pixels.
///
/// The box is stored unrotated, in sprite coordinates, and rotated around
/// `pivot` by `angle`. `x1 < x0` (or `y1 < y0`) means the content is flipped.
struct TransformBox: Equatable, Sendable {
    var x0: Double
    var y0: Double
    var x1: Double
    var y1: Double
    /// Radians, clockwise on screen (y points down).
    var angle: Double = 0
    var pivot: CGPoint

    init(rect: PixelRect) {
        x0 = Double(rect.minX)
        y0 = Double(rect.minY)
        x1 = Double(rect.maxX + 1)
        y1 = Double(rect.maxY + 1)
        pivot = CGPoint(x: (x0 + x1) / 2, y: (y0 + y1) / 2)
    }

    var width: Double { abs(x1 - x0) }
    var height: Double { abs(y1 - y0) }
    var center: CGPoint { CGPoint(x: (x0 + x1) / 2, y: (y0 + y1) / 2) }

    private func rotate(_ p: CGPoint, by a: Double) -> CGPoint {
        let dx = p.x - pivot.x, dy = p.y - pivot.y
        return CGPoint(x: pivot.x + dx * cos(a) - dy * sin(a), y: pivot.y + dx * sin(a) + dy * cos(a))
    }

    /// Unrotated box space → sprite space.
    func toWorld(_ p: CGPoint) -> CGPoint { rotate(p, by: angle) }
    /// Sprite space → unrotated box space.
    func toLocal(_ p: CGPoint) -> CGPoint { rotate(p, by: -angle) }

    /// Handle positions in sprite space, clockwise from the top-left corner:
    /// corners at even indices, edge midpoints at odd ones.
    var handles: [CGPoint] {
        let mx = (x0 + x1) / 2, my = (y0 + y1) / 2
        return [(x0, y0), (mx, y0), (x1, y0), (x1, my), (x1, y1), (mx, y1), (x0, y1), (x0, my)]
            .map { toWorld(CGPoint(x: $0.0, y: $0.1)) }
    }

    var corners: [CGPoint] { [handles[0], handles[2], handles[4], handles[6]] }

    func contains(_ p: CGPoint) -> Bool {
        let l = toLocal(p)
        return l.x >= min(x0, x1) && l.x <= max(x0, x1) && l.y >= min(y0, y1) && l.y <= max(y0, y1)
    }

    mutating func translate(dx: Double, dy: Double) {
        x0 += dx; x1 += dx; y0 += dy; y1 += dy
        pivot.x += dx; pivot.y += dy
    }

    /// Drags a scale handle to `point` (sprite space). Edges snap to whole
    /// pixels; dragging past the opposite edge flips the content.
    mutating func drag(handle: Int, to point: CGPoint, keepAspect: Bool, aspect: Double) {
        let l = toLocal(point)
        let moveLeft = [0, 6, 7].contains(handle), moveRight = [2, 3, 4].contains(handle)
        let moveTop = [0, 1, 2].contains(handle), moveBottom = [4, 5, 6].contains(handle)
        func snapped(_ v: Double, avoiding other: Double, previous: Double) -> Double {
            var r = v.rounded()
            if r == other { r = previous > other ? other + 1 : other - 1 }
            return r
        }
        if moveLeft { x0 = snapped(l.x, avoiding: x1, previous: x0) }
        if moveRight { x1 = snapped(l.x, avoiding: x0, previous: x1) }
        if moveTop { y0 = snapped(l.y, avoiding: y1, previous: y0) }
        if moveBottom { y1 = snapped(l.y, avoiding: y0, previous: y1) }
        guard keepAspect, aspect > 0 else { return }
        let w = x1 - x0, h = y1 - y0
        if handle % 2 == 0 {
            // Corner: follow the larger change, keep the other edge's sign.
            let newH = (abs(w) / aspect).rounded() * (h < 0 ? -1 : 1)
            if moveTop { y0 = y1 - newH } else { y1 = y0 + newH }
        } else if handle == 1 || handle == 5 {
            let newW = (abs(h) * aspect).rounded() * (w < 0 ? -1 : 1)
            let cx = (x0 + x1) / 2
            x0 = (cx - newW / 2).rounded(); x1 = x0 + newW
        } else {
            let newH = (abs(w) / aspect).rounded() * (h < 0 ? -1 : 1)
            let cy = (y0 + y1) / 2
            y0 = (cy - newH / 2).rounded(); y1 = y0 + newH
        }
    }

    /// Moves the pivot without moving the content.
    mutating func setPivot(_ p: CGPoint) {
        // Rotating around a different pivot would shift the content by
        // (I − R)(P − P′); move the box by R⁻¹(P − P′) − (P − P′) to cancel it.
        let delta = CGPoint(x: pivot.x - p.x, y: pivot.y - p.y)
        let back = CGPoint(x: delta.x * cos(-angle) - delta.y * sin(-angle), y: delta.x * sin(-angle) + delta.y * cos(-angle))
        let dx = back.x - delta.x, dy = back.y - delta.y
        pivot = p
        x0 += dx; x1 += dx; y0 += dy; y1 += dy
    }

    /// Bounding box of the rotated box, in whole pixels.
    var pixelBounds: PixelRect {
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return PixelRect(
            minX: Int(xs.min()!.rounded(.down)), minY: Int(ys.min()!.rounded(.down)),
            maxX: Int(xs.max()!.rounded(.up)) - 1, maxY: Int(ys.max()!.rounded(.up)) - 1
        )
    }
}

/// Pixels lifted from a cel (or pasted) that can be moved, scaled, rotated
/// and flipped before being dropped back into the cel.
struct FloatingSelection: Sendable {
    let celKey: CelKey
    var source: PixelImage
    /// Which source pixels belong to the selection (same size as `source`).
    var sourceMask: SelectionMask
    var box: TransformBox
    var algorithm: RotationAlgorithm = .rotSprite
    /// Where the box was when the pixels were lifted, for stretch moves.
    let startCenter: CGPoint
    private var upscaled: PixelImage?
    private var upscaledMask: SelectionMask?

    init(celKey: CelKey, source: PixelImage, sourceMask: SelectionMask, at origin: PixelPoint) {
        self.celKey = celKey
        self.source = source
        self.sourceMask = sourceMask
        self.box = TransformBox(rect: PixelRect(minX: origin.x, minY: origin.y, maxX: origin.x + source.width - 1, maxY: origin.y + source.height - 1))
        self.startCenter = box.center
    }

    var aspect: Double { Double(source.width) / Double(source.height) }

    /// Exact 90° turn of the source pixels; the box keeps its centre.
    mutating func rotate90(clockwise: Bool) {
        bakeFlips()
        source = source.rotated90(clockwise: clockwise)
        sourceMask = sourceMask.rotated90(clockwise: clockwise)
        upscaled = nil
        upscaledMask = nil
        let c = box.center, w = box.width, h = box.height
        box.x0 = (c.x - h / 2).rounded(.down)
        box.x1 = box.x0 + h
        box.y0 = (c.y - w / 2).rounded(.down)
        box.y1 = box.y0 + w
    }

    /// Moves any flip from the box into the source pixels, so the box is unflipped.
    private mutating func bakeFlips() {
        if box.x1 < box.x0 {
            source = source.flipped(horizontal: true)
            sourceMask = sourceMask.flipped(horizontal: true)
            swap(&box.x0, &box.x1)
        }
        if box.y1 < box.y0 {
            source = source.flipped(horizontal: false)
            sourceMask = sourceMask.flipped(horizontal: false)
            swap(&box.y0, &box.y1)
        }
    }

    mutating func flip(horizontal: Bool) {
        if horizontal { swap(&box.x0, &box.x1) } else { swap(&box.y0, &box.y1) }
    }

    private var needsRotSprite: Bool {
        algorithm == .rotSprite && abs(box.angle.remainder(dividingBy: .pi / 2)) > 0.0001
    }

    /// Renders the floating pixels into sprite space. Returns the pixels
    /// (size of `bounds`), their selection mask over the whole sprite, and bounds.
    mutating func render(spriteWidth: Int, spriteHeight: Int) -> (image: PixelImage, origin: PixelPoint, mask: SelectionMask) {
        var mask = SelectionMask(width: spriteWidth, height: spriteHeight)
        guard let bounds = box.pixelBounds.clipped(width: spriteWidth, height: spriteHeight) else {
            return (PixelImage(width: 1, height: 1), PixelPoint(x: 0, y: 0), mask)
        }
        let factor = needsRotSprite ? 8 : 1
        if factor > 1 && upscaled == nil {
            upscaled = source.scale2x().scale2x().scale2x()
            upscaledMask = sourceMask.scaled(by: 8)
        }
        let src = factor > 1 ? upscaled! : source
        let srcMask = factor > 1 ? upscaledMask! : sourceMask
        let w = bounds.maxX - bounds.minX + 1, h = bounds.maxY - bounds.minY + 1
        var out = PixelImage(width: w, height: h)
        let sx = Double(src.width) / (box.x1 - box.x0), sy = Double(src.height) / (box.y1 - box.y0)
        for y in bounds.minY...bounds.maxY {
            for x in bounds.minX...bounds.maxX {
                let l = box.toLocal(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5))
                let u = Int(((l.x - box.x0) * sx).rounded(.down))
                let v = Int(((l.y - box.y0) * sy).rounded(.down))
                guard u >= 0, v >= 0, u < src.width, v < src.height, srcMask[u, v] else { continue }
                mask[x, y] = true
                out[x - bounds.minX, y - bounds.minY] = src[u, v]
            }
        }
        return (out, PixelPoint(x: bounds.minX, y: bounds.minY), mask)
    }

    /// `render`, with the gap between where the pixels were lifted and where
    /// they are now filled by their trailing edge, so the moved part stays
    /// joined to the rest and stretches it (Aseprite's Ctrl+drag). The mask
    /// grows to cover the stretch.
    mutating func renderStretched(spriteWidth: Int, spriteHeight: Int) -> (image: PixelImage, origin: PixelPoint, mask: SelectionMask) {
        let moved = render(spriteWidth: spriteWidth, spriteHeight: spriteHeight)
        let dx = Int((box.center.x - startCenter.x).rounded()), dy = Int((box.center.y - startCenter.y).rounded())
        let steps = max(abs(dx), abs(dy))
        guard steps > 0, let rect = moved.mask.bounds else { return moved }
        let back = PixelRect(minX: rect.minX - dx, minY: rect.minY - dy, maxX: rect.maxX - dx, maxY: rect.maxY - dy)
        guard let swept = rect.union(back).clipped(width: spriteWidth, height: spriteHeight) else { return moved }
        var out = PixelImage(width: swept.maxX - swept.minX + 1, height: swept.maxY - swept.minY + 1)
        var mask = SelectionMask(width: spriteWidth, height: spriteHeight)
        // A copy at every step from the start to just before the end, each over
        // the last; then the pixels themselves, unchanged, on top.
        for step in 0...steps {
            let ox = Int((Double(dx * step) / Double(steps)).rounded()) - dx
            let oy = Int((Double(dy * step) / Double(steps)).rounded()) - dy
            let last = step == steps
            for y in rect.minY...rect.maxY {
                for x in rect.minX...rect.maxX where moved.mask[x, y] {
                    let tx = x + ox, ty = y + oy
                    guard tx >= swept.minX, ty >= swept.minY, tx <= swept.maxX, ty <= swept.maxY else { continue }
                    let p = moved.image[x - moved.origin.x, y - moved.origin.y]
                    mask[tx, ty] = true
                    if last || p.a != 0 { out[tx - swept.minX, ty - swept.minY] = p }
                }
            }
        }
        return (out, PixelPoint(x: swept.minX, y: swept.minY), mask)
    }
}

// MARK: - Image operations

extension PixelImage {
    func cropped(to r: PixelRect) -> PixelImage {
        var out = PixelImage(width: r.maxX - r.minX + 1, height: r.maxY - r.minY + 1)
        for y in r.minY...r.maxY where y >= 0 && y < height {
            for x in r.minX...r.maxX where x >= 0 && x < width {
                out[x - r.minX, y - r.minY] = self[x, y]
            }
        }
        return out
    }

    func flipped(horizontal: Bool) -> PixelImage {
        var out = self
        for y in 0..<height {
            for x in 0..<width {
                out[x, y] = horizontal ? self[width - 1 - x, y] : self[x, height - 1 - y]
            }
        }
        return out
    }

    func rotated90(clockwise: Bool) -> PixelImage {
        var out = PixelImage(width: height, height: width)
        for y in 0..<height {
            for x in 0..<width {
                if clockwise { out[height - 1 - y, x] = self[x, y] } else { out[y, width - 1 - x] = self[x, y] }
            }
        }
        return out
    }

    /// Bounds of the non-transparent pixels.
    var opaqueBounds: PixelRect? { SelectionMask.opaquePixels(of: self).bounds }

    /// Scale2x (EPX): doubles the size and keeps diagonal edges smooth.
    func scale2x() -> PixelImage {
        var out = PixelImage(width: width * 2, height: height * 2)
        for y in 0..<height {
            for x in 0..<width {
                let p = self[x, y]
                let a = y > 0 ? self[x, y - 1] : p
                let b = x < width - 1 ? self[x + 1, y] : p
                let c = x > 0 ? self[x - 1, y] : p
                let d = y < height - 1 ? self[x, y + 1] : p
                out[2 * x, 2 * y] = (c == a && c != d && a != b) ? a : p
                out[2 * x + 1, 2 * y] = (a == b && a != c && b != d) ? b : p
                out[2 * x, 2 * y + 1] = (d == c && d != b && c != a) ? c : p
                out[2 * x + 1, 2 * y + 1] = (b == d && b != a && d != c) ? d : p
            }
        }
        return out
    }
}

extension SelectionMask {
    func cropped(to r: PixelRect) -> SelectionMask {
        var out = SelectionMask(width: r.maxX - r.minX + 1, height: r.maxY - r.minY + 1)
        for y in r.minY...r.maxY where y >= 0 && y < height {
            for x in r.minX...r.maxX where x >= 0 && x < width {
                out[x - r.minX, y - r.minY] = self[x, y]
            }
        }
        return out
    }

    func flipped(horizontal: Bool) -> SelectionMask {
        var out = self
        for y in 0..<height {
            for x in 0..<width {
                out[x, y] = horizontal ? self[width - 1 - x, y] : self[x, height - 1 - y]
            }
        }
        return out
    }

    func rotated90(clockwise: Bool) -> SelectionMask {
        var out = SelectionMask(width: height, height: width)
        for y in 0..<height {
            for x in 0..<width where self[x, y] {
                if clockwise { out[height - 1 - y, x] = true } else { out[y, width - 1 - x] = true }
            }
        }
        return out
    }

    func scaled(by factor: Int) -> SelectionMask {
        var out = SelectionMask(width: width * factor, height: height * factor)
        for y in 0..<out.height {
            for x in 0..<out.width { out[x, y] = self[x / factor, y / factor] }
        }
        return out
    }
}

// MARK: - Canvas operations

extension Sprite {
    /// Union of the non-transparent pixels of every cel.
    var contentBounds: PixelRect? {
        cels.values.compactMap(\.opaqueBounds).reduce(nil as PixelRect?) { $0?.union($1) ?? $1 }
    }

    /// Changes the canvas to `rect`, cropping (or extending) every cel.
    mutating func crop(to rect: PixelRect) {
        width = rect.maxX - rect.minX + 1
        height = rect.maxY - rect.minY + 1
        cels = cels.compactMapValues { image in
            let cropped = image.cropped(to: rect)
            return cropped.isEmpty ? nil : cropped
        }
    }

    /// Aseprite's Canvas Size: a new width and height, growing or shrinking
    /// away from `anchor` (column and row, 0 to 2: left/top, centre, right/bottom).
    /// Cels, slices and the grid keep their place on the drawing. Returns how far
    /// the drawing moved.
    @discardableResult
    mutating func resizeCanvas(width newWidth: Int, height newHeight: Int, anchor: (x: Int, y: Int)) -> (dx: Int, dy: Int) {
        let dx = (newWidth - width) * anchor.x / 2, dy = (newHeight - height) * anchor.y / 2
        return resizeCanvas(to: PixelRect(minX: -dx, minY: -dy, maxX: newWidth - 1 - dx, maxY: newHeight - 1 - dy))
    }

    /// The canvas becomes `rect` (in the current canvas's coordinates; it can
    /// reach past its edges to grow). Returns how far the drawing moved.
    @discardableResult
    mutating func resizeCanvas(to rect: PixelRect) -> (dx: Int, dy: Int) {
        let dx = -rect.minX, dy = -rect.minY
        crop(to: rect)
        for i in slices.indices {
            for k in slices[i].keys.indices { slices[i].keys[k].bounds = slices[i].keys[k].bounds.offsetBy(dx: dx, dy: dy) }
        }
        grid.offsetX = ((grid.offsetX + dx) % grid.width + grid.width) % grid.width
        grid.offsetY = ((grid.offsetY + dy) % grid.height + grid.height) % grid.height
        return (dx, dy)
    }

    mutating func rotateCanvas(clockwise: Bool) {
        swap(&width, &height)
        cels = cels.mapValues { $0.rotated90(clockwise: clockwise) }
    }

    mutating func flipCanvas(horizontal: Bool) {
        cels = cels.mapValues { $0.flipped(horizontal: horizontal) }
    }
}
