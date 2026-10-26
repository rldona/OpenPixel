import Foundation

/// Aseprite's grid (View > Grid Settings): cells of any size, shifted by an
/// offset. Selections and moves can snap to it, the paint bucket can stop at
/// its lines, and tilemaps use it as their tile size.
struct GridSettings: Codable, Equatable, Sendable {
    var width = 16
    var height = 16
    var offsetX = 0
    var offsetY = 0

    /// The cell holding pixel `p`.
    func cell(containing p: PixelPoint) -> PixelRect {
        let col = Int((Double(p.x - offsetX) / Double(width)).rounded(.down))
        let row = Int((Double(p.y - offsetY) / Double(height)).rounded(.down))
        let x = offsetX + col * width, y = offsetY + row * height
        return PixelRect(minX: x, minY: y, maxX: x + width - 1, maxY: y + height - 1)
    }

    /// The cells covering the rectangle between two pixels.
    func cells(from a: PixelPoint, to b: PixelPoint) -> PixelRect {
        cell(containing: a).union(cell(containing: b))
    }

    /// The grid corner (a cell's top-left) closest to `p`.
    func closestVertex(to p: PixelPoint) -> PixelPoint {
        PixelPoint(
            x: offsetX + Int((Double(p.x - offsetX) / Double(width)).rounded()) * width,
            y: offsetY + Int((Double(p.y - offsetY) / Double(height)).rounded()) * height
        )
    }

    /// A move of `d` pixels rounded to whole cells.
    func snap(dx: Double, dy: Double) -> (Double, Double) {
        ((dx / Double(width)).rounded() * Double(width), (dy / Double(height)).rounded() * Double(height))
    }
}
