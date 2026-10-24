import Foundation

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

    /// 4-connected flood fill of the region that has the same color as `start`.
    static func floodFill(_ image: inout PixelImage, at start: PixelPoint, with color: PixelColor) {
        guard image.contains(start) else { return }
        let target = image[start]
        guard target != color else { return }
        var stack = [start]
        while let p = stack.popLast() {
            guard image.contains(p), image[p] == target else { continue }
            image[p] = color
            stack.append(PixelPoint(x: p.x + 1, y: p.y))
            stack.append(PixelPoint(x: p.x - 1, y: p.y))
            stack.append(PixelPoint(x: p.x, y: p.y + 1))
            stack.append(PixelPoint(x: p.x, y: p.y - 1))
        }
    }
}
