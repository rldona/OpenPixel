import Foundation

/// How a new selection shape combines with the current selection.
/// https://www.aseprite.org/docs/selecting/
enum SelectionMode: String, CaseIterable, Identifiable {
    case replace, add, subtract, intersect
    var id: String { rawValue }
}

/// Which pixels of the sprite are selected. Same size as the sprite.
struct SelectionMask: Equatable, Sendable {
    let width: Int
    let height: Int
    private(set) var bits: [Bool]

    init(width: Int, height: Int, filled: Bool = false) {
        self.width = width
        self.height = height
        self.bits = Array(repeating: filled, count: width * height)
    }

    init(width: Int, height: Int, bits: [Bool]) {
        precondition(bits.count == width * height, "Mask size does not match")
        self.width = width
        self.height = height
        self.bits = bits
    }

    func contains(_ p: PixelPoint) -> Bool {
        p.x >= 0 && p.y >= 0 && p.x < width && p.y < height && bits[p.y * width + p.x]
    }

    subscript(x: Int, y: Int) -> Bool {
        get { bits[y * width + x] }
        set { bits[y * width + x] = newValue }
    }

    var isEmpty: Bool { !bits.contains(true) }

    var bounds: PixelRect? {
        var rect: PixelRect?
        for y in 0..<height {
            for x in 0..<width where bits[y * width + x] {
                if rect == nil {
                    rect = PixelRect(minX: x, minY: y, maxX: x, maxY: y)
                } else {
                    rect!.minX = min(rect!.minX, x)
                    rect!.maxX = max(rect!.maxX, x)
                    rect!.maxY = y
                }
            }
        }
        return rect
    }

    // MARK: Shapes

    static func rect(_ r: PixelRect, width: Int, height: Int) -> SelectionMask {
        var mask = SelectionMask(width: width, height: height)
        guard let r = r.clipped(width: width, height: height) else { return mask }
        for y in r.minY...r.maxY {
            for x in r.minX...r.maxX { mask[x, y] = true }
        }
        return mask
    }

    static func points(_ points: [PixelPoint], width: Int, height: Int) -> SelectionMask {
        var mask = SelectionMask(width: width, height: height)
        for p in points where p.x >= 0 && p.y >= 0 && p.x < width && p.y < height {
            mask[p.x, p.y] = true
        }
        return mask
    }

    static func ellipse(from a: PixelPoint, to b: PixelPoint, width: Int, height: Int) -> SelectionMask {
        points(Raster.ellipse(from: a, to: b, filled: true), width: width, height: height)
    }

    /// Lasso: pixels whose centre is inside the closed path (even-odd), plus the path itself.
    static func polygon(_ path: [PixelPoint], width: Int, height: Int) -> SelectionMask {
        guard let first = path.first else { return SelectionMask(width: width, height: height) }
        let closed = path + [first]
        var outline: [PixelPoint] = []
        for i in 1..<closed.count { outline += Raster.line(from: closed[i - 1], to: closed[i]) }
        var mask = points(outline, width: width, height: height)
        let ys = path.map(\.y)
        guard let minY = ys.min(), let maxY = ys.max() else { return mask }
        for y in max(0, minY)...min(height - 1, maxY) {
            let yc = Double(y) + 0.5
            var crossings: [Double] = []
            for i in 1..<closed.count {
                let a = closed[i - 1], b = closed[i]
                let ay = Double(a.y) + 0.5, by = Double(b.y) + 0.5
                guard (ay <= yc) != (by <= yc) else { continue }
                let t = (yc - ay) / (by - ay)
                crossings.append(Double(a.x) + 0.5 + t * Double(b.x - a.x))
            }
            crossings.sort()
            var i = 0
            while i + 1 < crossings.count {
                let from = max(0, Int((crossings[i] - 0.5).rounded(.up)))
                let to = min(width - 1, Int((crossings[i + 1] - 0.5).rounded(.down)))
                if from <= to { for x in from...to { mask[x, y] = true } }
                i += 2
            }
        }
        return mask
    }

    /// Magic wand: pixels whose color is within `tolerance` (0–255, per channel)
    /// of the color at `start`; only the connected area when `contiguous`.
    static func magicWand(in image: PixelImage, at start: PixelPoint, tolerance: Int, contiguous: Bool) -> SelectionMask {
        var mask = SelectionMask(width: image.width, height: image.height)
        guard image.contains(start) else { return mask }
        let target = image[start]
        func matches(_ c: PixelColor) -> Bool {
            if target.a == 0 && c.a == 0 { return true }
            return abs(Int(c.r) - Int(target.r)) <= tolerance && abs(Int(c.g) - Int(target.g)) <= tolerance
                && abs(Int(c.b) - Int(target.b)) <= tolerance && abs(Int(c.a) - Int(target.a)) <= tolerance
        }
        if !contiguous {
            for i in image.pixels.indices where matches(image.pixels[i]) { mask.bits[i] = true }
            return mask
        }
        var stack = [start]
        while let p = stack.popLast() {
            guard image.contains(p), !mask[p.x, p.y], matches(image[p]) else { continue }
            mask[p.x, p.y] = true
            stack.append(PixelPoint(x: p.x + 1, y: p.y))
            stack.append(PixelPoint(x: p.x - 1, y: p.y))
            stack.append(PixelPoint(x: p.x, y: p.y + 1))
            stack.append(PixelPoint(x: p.x, y: p.y - 1))
        }
        return mask
    }

    /// The drawn piece of `image` under `start`: its non-transparent pixels
    /// that touch each other, diagonals included, whatever their color.
    static func piece(of image: PixelImage, at start: PixelPoint) -> SelectionMask {
        var mask = SelectionMask(width: image.width, height: image.height)
        guard image.contains(start), image[start].a != 0 else { return mask }
        var stack = [start]
        while let p = stack.popLast() {
            guard image.contains(p), !mask[p.x, p.y], image[p].a != 0 else { continue }
            mask[p.x, p.y] = true
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 { stack.append(PixelPoint(x: p.x + dx, y: p.y + dy)) }
            }
        }
        return mask
    }

    /// Every non-transparent pixel of `image` (Aseprite's "select layer content").
    static func opaquePixels(of image: PixelImage) -> SelectionMask {
        SelectionMask(width: image.width, height: image.height, bits: image.pixels.map { $0.a != 0 })
    }

    // MARK: Operations

    func combined(with shape: SelectionMask, mode: SelectionMode) -> SelectionMask {
        var out = self
        for i in bits.indices {
            switch mode {
            case .replace: out.bits[i] = shape.bits[i]
            case .add: out.bits[i] = bits[i] || shape.bits[i]
            case .subtract: out.bits[i] = bits[i] && !shape.bits[i]
            case .intersect: out.bits[i] = bits[i] && shape.bits[i]
            }
        }
        return out
    }

    func inverted() -> SelectionMask {
        SelectionMask(width: width, height: height, bits: bits.map { !$0 })
    }

    /// Grows the selection by `amount` pixels in every direction (square kernel).
    func expanded(by amount: Int) -> SelectionMask {
        guard amount > 0 else { return self }
        var horizontal = SelectionMask(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width where bits[y * width + x] {
                for dx in max(0, x - amount)...min(width - 1, x + amount) { horizontal[dx, y] = true }
            }
        }
        var out = SelectionMask(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width where horizontal[x, y] {
                for dy in max(0, y - amount)...min(height - 1, y + amount) { out[x, dy] = true }
            }
        }
        return out
    }

    /// Shrinks the selection by `amount` pixels. Pixels at the canvas edge count as inside.
    func contracted(by amount: Int) -> SelectionMask {
        guard amount > 0 else { return self }
        var outside = inverted().expanded(by: amount)
        // The canvas edge is not a selection boundary.
        for i in bits.indices where !bits[i] { outside.bits[i] = true }
        return outside.inverted()
    }

    /// A band `amount` pixels wide just inside the selection's edge.
    func border(_ amount: Int) -> SelectionMask {
        combined(with: contracted(by: amount), mode: .subtract)
    }

    /// Edges between selected and unselected pixels, as segments between pixel
    /// corners, with collinear runs merged. Used to draw the marching ants.
    func outline() -> [(PixelPoint, PixelPoint)] {
        var segments: [(PixelPoint, PixelPoint)] = []
        func selected(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < width && y < height && bits[y * width + x] }
        // Horizontal edges: between row y-1 and y.
        for y in 0...height {
            var start: Int?
            for x in 0...width {
                let edge = x < width && selected(x, y - 1) != selected(x, y)
                if edge, start == nil { start = x }
                if !edge, let s = start {
                    segments.append((PixelPoint(x: s, y: y), PixelPoint(x: x, y: y)))
                    start = nil
                }
            }
        }
        // Vertical edges: between column x-1 and x.
        for x in 0...width {
            var start: Int?
            for y in 0...height {
                let edge = y < height && selected(x - 1, y) != selected(x, y)
                if edge, start == nil { start = y }
                if !edge, let s = start {
                    segments.append((PixelPoint(x: x, y: s), PixelPoint(x: x, y: y)))
                    start = nil
                }
            }
        }
        return segments
    }
}
