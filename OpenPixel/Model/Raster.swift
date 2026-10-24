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

    /// Outline or filled rectangle between two opposite corners, with corners
    /// rounded by `radius` pixels (clamped to half the shorter side).
    static func rectangle(from a: PixelPoint, to b: PixelPoint, filled: Bool, radius: Int = 0) -> [PixelPoint] {
        let x0 = min(a.x, b.x), x1 = max(a.x, b.x), y0 = min(a.y, b.y), y1 = max(a.y, b.y)
        let r = max(0, min(radius, (x1 - x0) / 2, (y1 - y0) / 2))
        // Inside test: away from the corners everything is in; in a corner the
        // pixel's centre must be inside the circle of radius r + ½.
        func inside(_ x: Int, _ y: Int) -> Bool {
            guard x >= x0, x <= x1, y >= y0, y <= y1 else { return false }
            guard r > 0 else { return true }
            let cx = x < x0 + r ? x0 + r : (x > x1 - r ? x1 - r : x)
            let cy = y < y0 + r ? y0 + r : (y > y1 - r ? y1 - r : y)
            let dx = Double(x - cx), dy = Double(y - cy)
            return dx * dx + dy * dy <= (Double(r) + 0.5) * (Double(r) + 0.5)
        }
        var points: [PixelPoint] = []
        for y in y0...y1 {
            for x in x0...x1 where inside(x, y) {
                let edge = !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1)
                if filled || edge { points.append(PixelPoint(x: x, y: y)) }
            }
        }
        return points
    }

    /// Cubic Bézier from `a` to `b` bent by two control points, as connected pixels.
    static func curve(from a: PixelPoint, _ c1: PixelPoint, _ c2: PixelPoint, to b: PixelPoint) -> [PixelPoint] {
        // Not bent yet: exactly what the line tool draws.
        if c1 == a && c2 == b { return line(from: a, to: b) }
        func length(_ p: PixelPoint, _ q: PixelPoint) -> Double { Double(max(abs(p.x - q.x), abs(p.y - q.y))) }
        let steps = max(1, Int(length(a, c1) + length(c1, c2) + length(c2, b)) * 2)
        var points: [PixelPoint] = []
        var previous = a
        for i in 1...steps {
            let t = Double(i) / Double(steps), u = 1 - t
            func axis(_ p0: Int, _ p1: Int, _ p2: Int, _ p3: Int) -> Int {
                Int((u * u * u * Double(p0) + 3 * u * u * t * Double(p1) + 3 * u * t * t * Double(p2) + t * t * t * Double(p3)).rounded())
            }
            let p = PixelPoint(x: axis(a.x, c1.x, c2.x, b.x), y: axis(a.y, c1.y, c2.y, b.y))
            guard p != previous else { continue }
            points += line(from: previous, to: p).dropLast()
            previous = p
        }
        points.append(b)
        // Drop the L-corners the sampling leaves, so the curve stays 1 px thin.
        var thin: [PixelPoint] = []
        for p in points {
            if thin.count >= 2 {
                let m = thin[thin.count - 1], o = thin[thin.count - 2]
                if abs(o.x - p.x) == 1 && abs(o.y - p.y) == 1 && (m.x == o.x || m.y == o.y) && (m.x == p.x || m.y == p.y) {
                    thin.removeLast()
                }
            }
            if thin.last != p { thin.append(p) }
        }
        return thin
    }

    /// A closed polygon through `vertices`: its edges, plus the inside when `filled`.
    static func polygon(_ vertices: [PixelPoint], filled: Bool) -> [PixelPoint] {
        guard let first = vertices.first else { return [] }
        guard filled else {
            let closed = vertices + [first]
            var outline: [PixelPoint] = [first]
            for i in 1..<closed.count { outline += line(from: closed[i - 1], to: closed[i]).dropFirst() }
            return outline
        }
        let xs = vertices.map(\.x), ys = vertices.map(\.y)
        let minX = xs.min()!, minY = ys.min()!
        let shifted = vertices.map { PixelPoint(x: $0.x - minX, y: $0.y - minY) }
        let mask = SelectionMask.polygon(shifted, width: xs.max()! - minX + 1, height: ys.max()! - minY + 1)
        var points: [PixelPoint] = []
        for i in mask.bits.indices where mask.bits[i] {
            points.append(PixelPoint(x: i % mask.width + minX, y: i / mask.width + minY))
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

    /// The pixels the paint bucket reaches from `start`: those whose color in
    /// `reference` is within `tolerance` of the start color, connected to it
    /// (through edges, or corners too with `diagonal`) when `contiguous`,
    /// and inside `mask` if given.
    static func fillRegion(
        in reference: PixelImage, at start: PixelPoint, tolerance: Int = 0, contiguous: Bool = true,
        diagonal: Bool = false, within mask: SelectionMask? = nil
    ) -> SelectionMask {
        let w = reference.width, h = reference.height
        var region = [Bool](repeating: false, count: w * h)
        guard reference.contains(start), mask?.contains(start) ?? true else { return SelectionMask(width: w, height: h, bits: region) }
        let target = reference[start]
        func reachable(_ i: Int) -> Bool {
            reference.pixels[i].matches(target, tolerance: tolerance) && (mask?.bits[i] ?? true)
        }
        guard contiguous else {
            for i in reference.pixels.indices where reachable(i) { region[i] = true }
            return SelectionMask(width: w, height: h, bits: region)
        }
        var stack = [start.y * w + start.x]
        region[stack[0]] = true
        while let i = stack.popLast() {
            let x = i % w, y = i / w
            for dy in -1...1 {
                for dx in -1...1 where (dx != 0 || dy != 0) && (diagonal || dx == 0 || dy == 0) {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                    let j = ny * w + nx
                    guard !region[j], reachable(j) else { continue }
                    region[j] = true
                    stack.append(j)
                }
            }
        }
        return SelectionMask(width: w, height: h, bits: region)
    }

    /// Bayer ordered-dither matrix of size n (2, 4 or 8), values 0..<n².
    static func bayer(_ n: Int) -> [[Int]] {
        guard n > 1 else { return [[0]] }
        let half = bayer(n / 2)
        var m = [[Int]](repeating: [Int](repeating: 0, count: n), count: n)
        for y in 0..<n {
            for x in 0..<n {
                let base = 4 * half[y % (n / 2)][x % (n / 2)]
                let quadrant = [[0, 2], [3, 1]][y / (n / 2)][x / (n / 2)]
                m[y][x] = base + quadrant
            }
        }
        return m
    }
}
