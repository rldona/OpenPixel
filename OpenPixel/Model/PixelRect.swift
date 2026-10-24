import Foundation

/// An inclusive rectangle of pixels, used to redraw only what a stroke touched.
struct PixelRect: Equatable, Sendable {
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int

    static func full(width: Int, height: Int) -> PixelRect {
        PixelRect(minX: 0, minY: 0, maxX: width - 1, maxY: height - 1)
    }

    /// Bounding box of `points`, grown by `lower`/`upper` on each axis (brush extent).
    init?(bounding points: some Sequence<PixelPoint>, lower: Int = 0, upper: Int = 0) {
        var iterator = points.makeIterator()
        guard let first = iterator.next() else { return nil }
        var rect = PixelRect(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        while let p = iterator.next() {
            rect.minX = min(rect.minX, p.x)
            rect.minY = min(rect.minY, p.y)
            rect.maxX = max(rect.maxX, p.x)
            rect.maxY = max(rect.maxY, p.y)
        }
        self.init(minX: rect.minX + lower, minY: rect.minY + lower, maxX: rect.maxX + upper, maxY: rect.maxY + upper)
    }

    init(minX: Int, minY: Int, maxX: Int, maxY: Int) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    func union(_ other: PixelRect) -> PixelRect {
        PixelRect(minX: min(minX, other.minX), minY: min(minY, other.minY), maxX: max(maxX, other.maxX), maxY: max(maxY, other.maxY))
    }

    func clipped(width: Int, height: Int) -> PixelRect? {
        let rect = PixelRect(minX: max(0, minX), minY: max(0, minY), maxX: min(width - 1, maxX), maxY: min(height - 1, maxY))
        return rect.minX <= rect.maxX && rect.minY <= rect.maxY ? rect : nil
    }
}
