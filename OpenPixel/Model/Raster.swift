import Foundation

enum BrushShape: String, CaseIterable, Identifiable {
    case square, circle
    var id: String { rawValue }
}

enum Raster {
    /// Bresenham line, both ends included.
    static func line(from a: PixelPoint, to b: PixelPoint) -> [PixelPoint] {
        var points: [PixelPoint] = []
        var x = a.x, y = a.y
        let dx = abs(b.x - a.x), dy = -abs(b.y - a.y)
        let sx = a.x < b.x ? 1 : -1, sy = a.y < b.y ? 1 : -1
        var err = dx + dy
        while true {
            points.append(PixelPoint(x: x, y: y))
            if x == b.x && y == b.y { break }
            let e2 = 2 * err
            if e2 >= dy { err += dy; x += sx }
            if e2 <= dx { err += dx; y += sy }
        }
        return points
    }

    /// Pixels covered by a brush of `size` centred on the origin. Even sizes lean
    /// towards the bottom-right, like Aseprite. Circles of size ≤ 3 are full squares.
    static func brushOffsets(size: Int, shape: BrushShape) -> [PixelPoint] {
        let size = max(1, size)
        let start = -(size - 1) / 2
        let center = Double(size - 1) / 2
        let radius = Double(size) / 2
        var offsets: [PixelPoint] = []
        for dy in 0..<size {
            for dx in 0..<size {
                if shape == .circle {
                    let x = Double(dx) - center, y = Double(dy) - center
                    guard x * x + y * y <= radius * radius else { continue }
                }
                offsets.append(PixelPoint(x: start + dx, y: start + dy))
            }
        }
        return offsets
    }

    /// Outline or filled rectangle between two opposite corners.
    static func rectangle(from a: PixelPoint, to b: PixelPoint, filled: Bool) -> [PixelPoint] {
        let x0 = min(a.x, b.x), x1 = max(a.x, b.x), y0 = min(a.y, b.y), y1 = max(a.y, b.y)
        var points: [PixelPoint] = []
        for y in y0...y1 {
            for x in x0...x1 where filled || x == x0 || x == x1 || y == y0 || y == y1 {
                points.append(PixelPoint(x: x, y: y))
            }
        }
        return points
    }

    /// Ellipse inscribed in the rectangle between two opposite corners
    /// (Alois Zingl's integer algorithm, so tiny ellipses still look right).
    static func ellipse(from a: PixelPoint, to b: PixelPoint, filled: Bool) -> [PixelPoint] {
        var x0 = a.x, y0 = a.y, x1 = b.x, y1 = b.y
        var outline: [PixelPoint] = []
        func plot(_ x: Int, _ y: Int) { outline.append(PixelPoint(x: x, y: y)) }

        var w = abs(x1 - x0)
        let h = abs(y1 - y0)
        var b1 = h & 1
        var dx = 4 * (1 - w) * h * h
        var dy = 4 * (b1 + 1) * w * w
        var err = dx + dy + b1 * w * w
        if x0 > x1 { x0 = x1; x1 += w }
        if y0 > y1 { y0 = y1 }
        y0 += (h + 1) / 2
        y1 = y0 - b1
        w *= 8 * w
        b1 = 8 * h * h
        repeat {
            plot(x1, y0); plot(x0, y0); plot(x0, y1); plot(x1, y1)
            let e2 = 2 * err
            if e2 <= dy { y0 += 1; y1 -= 1; dy += w; err += dy }
            if e2 >= dx || 2 * err > dy { x0 += 1; x1 -= 1; dx += b1; err += dx }
        } while x0 <= x1
        while y0 - y1 <= h {
            plot(x0 - 1, y0); plot(x1 + 1, y0); y0 += 1
            plot(x0 - 1, y1); plot(x1 + 1, y1); y1 -= 1
        }

        guard filled else { return outline }
        // Fill each row between its leftmost and rightmost outline pixel.
        var rows: [Int: (Int, Int)] = [:]
        for p in outline {
            let row = rows[p.y] ?? (p.x, p.x)
            rows[p.y] = (min(row.0, p.x), max(row.1, p.x))
        }
        return rows.flatMap { y, span in (span.0...span.1).map { PixelPoint(x: $0, y: y) } }
    }

    /// Replaces every pixel of `start`'s color, connected or not, inside `mask` if given.
    static func replaceColor(_ image: inout PixelImage, at start: PixelPoint, with color: PixelColor, within mask: SelectionMask? = nil) {
        guard image.contains(start), mask?.contains(start) ?? true else { return }
        let target = image[start]
        guard target != color else { return }
        for i in image.pixels.indices where image.pixels[i] == target && (mask?.bits[i] ?? true) {
            image.pixels[i] = color
        }
    }

    /// 4-connected flood fill of the region that has the same color as `start`,
    /// staying inside `mask` if given.
    static func floodFill(_ image: inout PixelImage, at start: PixelPoint, with color: PixelColor, within mask: SelectionMask? = nil) {
        guard image.contains(start), mask?.contains(start) ?? true else { return }
        let target = image[start]
        guard target != color else { return }
        var stack = [start]
        while let p = stack.popLast() {
            guard image.contains(p), image[p] == target, mask?.contains(p) ?? true else { continue }
            image[p] = color
            stack.append(PixelPoint(x: p.x + 1, y: p.y))
            stack.append(PixelPoint(x: p.x - 1, y: p.y))
            stack.append(PixelPoint(x: p.x, y: p.y + 1))
            stack.append(PixelPoint(x: p.x, y: p.y - 1))
        }
    }
}
