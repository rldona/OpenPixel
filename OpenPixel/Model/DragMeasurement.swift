import Foundation

/// The size of the shape or selection being dragged, shown next to it on the
/// canvas, like the sizes Aseprite's status bar shows while dragging.
struct DragMeasurement: Equatable {
    /// The area it covers, in sprite pixels.
    var rect: PixelRect
    /// Where the drag started: the label goes by this corner, away from the finger.
    var origin: PixelPoint
    var text: String

    /// A rectangle, ellipse or selection: its width and height.
    init(rect: PixelRect, origin: PixelPoint) {
        self.rect = rect
        self.origin = origin
        text = "\(rect.maxX - rect.minX + 1) × \(rect.maxY - rect.minY + 1)"
    }

    /// A line: its width and height, how many pixels long it is and its angle,
    /// counterclockwise from the right as in Aseprite.
    init(lineFrom a: PixelPoint, to b: PixelPoint) {
        self.init(rect: PixelRect(minX: min(a.x, b.x), minY: min(a.y, b.y), maxX: max(a.x, b.x), maxY: max(a.y, b.y)), origin: a)
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(abs(dx), abs(dy)) + 1
        var degrees = Int((atan2(Double(-dy), Double(dx)) * 180 / .pi).rounded())
        if degrees == -180 { degrees = 180 }
        text += " · \(length) px · \(degrees)°"
    }
}
