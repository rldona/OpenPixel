import Foundation

/// Aseprite's Edit > FX > Outline: a one-pixel line of one color around what's
/// drawn (outside), or over its own edge (inside).
struct OutlineEffect: Hashable, Sendable {
    enum Place: String, CaseIterable, Identifiable, Sendable {
        case outside, inside
        var id: String { rawValue }
    }

    var place = Place.outside
    /// Which neighbours are looked at, row by row from the top left. The middle
    /// one is the pixel itself and is ignored.
    var matrix = OutlineEffect.circle
    var color = PixelColor.black
    /// What counts as empty. Clear means any fully transparent pixel.
    var background = PixelColor.clear
    /// Neighbours past an edge wrap around to the other side.
    var tiled = false

    /// Aseprite's four shapes: the plus gives round corners, the square sharp ones.
    static let circle = [false, true, false, true, false, true, false, true, false]
    static let square = [true, true, true, true, false, true, true, true, true]
    static let horizontal = [false, false, false, true, false, true, false, false, false]
    static let vertical = [false, true, false, false, false, false, false, true, false]

    private func isEmpty(_ c: PixelColor) -> Bool {
        background.a == 0 ? c.a == 0 : c == background
    }

    /// The image with the outline drawn, only inside `mask` when there is one.
    /// Neighbours are read from the whole image.
    func apply(to image: PixelImage, mask: SelectionMask?) -> PixelImage {
        let w = image.width, h = image.height
        let offsets = (0..<9).compactMap { i -> (Int, Int)? in
            i != 4 && matrix[i] ? (i % 3 - 1, i / 3 - 1) : nil
        }
        guard !offsets.isEmpty else { return image }
        let empty = image.pixels.map(isEmpty)
        var out = image
        for y in 0..<h {
            for x in 0..<w {
                let i = y * w + x
                guard mask?.bits[i] ?? true else { continue }
                // Outside paints empty pixels next to drawn ones; inside paints
                // drawn pixels next to empty ones (or the canvas edge).
                let wantsDrawnNeighbour = place == .outside
                guard empty[i] == wantsDrawnNeighbour else { continue }
                let touches = offsets.contains { dx, dy in
                    var nx = x + dx, ny = y + dy
                    if tiled {
                        nx = (nx % w + w) % w
                        ny = (ny % h + h) % h
                    } else if nx < 0 || ny < 0 || nx >= w || ny >= h {
                        return !wantsDrawnNeighbour
                    }
                    return empty[ny * w + nx] != wantsDrawnNeighbour
                }
                if touches { out.pixels[i] = color }
            }
        }
        return out
    }
}
