import Foundation

/// Where Arrange puts the selected element among the layers.
enum LayerArrangement {
    case front, forward, backward, back

    var isUp: Bool { self == .front || self == .forward }
    var isOneStep: Bool { self == .forward || self == .backward }
}

/// Arranging one cel inside its frame with its z-index, as Aseprite's Cel
/// Properties do, so a part can be behind in one frame and in front in another.
extension Sprite {
    /// The cels drawn in a frame, bottom to top.
    func drawnCels(frame: UUID) -> [CelKey] {
        drawOrder(frame: frame).compactMap { layer in
            let key = CelKey(layer: layer.id, frame: frame)
            return cels[key] != nil && !layer.isGroup && !layer.isReference ? key : nil
        }
    }

    /// Whether the cel can go further up (or down) in its frame. It doesn't go
    /// past `others` (the other cels being arranged with it) or under the background.
    func canArrangeCel(_ key: CelKey, up: Bool, others: Set<UUID> = []) -> Bool {
        let order = drawnCels(frame: key.frame)
        guard let index = order.firstIndex(of: key), !isBackground(key.layer) else { return false }
        let next = index + (up ? 1 : -1)
        guard order.indices.contains(next) else { return false }
        return !others.contains(order[next].layer) && (up || !isBackground(order[next].layer))
    }

    /// Moves a cel up or down the draw order of its frame by giving it a
    /// z-index. Only that cel's z-index changes when it can; otherwise the
    /// frame's z-indexes are worked out again. Returns whether anything moved.
    @discardableResult
    mutating func arrangeCel(_ key: CelKey, _ arrangement: LayerArrangement, others: Set<UUID> = []) -> Bool {
        var order = drawnCels(frame: key.frame)
        guard let from = order.firstIndex(of: key), canArrangeCel(key, up: arrangement.isUp, others: others) else { return false }
        // Where it goes: one cel up or down, or as far as it can.
        let step = arrangement.isUp ? 1 : -1
        var to = from + step
        if !arrangement.isOneStep {
            while order.indices.contains(to + step), !others.contains(order[to + step].layer),
                  arrangement.isUp || !isBackground(order[to + step].layer) {
                to += step
            }
        }
        order.remove(at: from)
        order.insert(key, at: to)
        place(key, in: order, at: to)
        return true
    }

    private func isBackground(_ layer: UUID) -> Bool {
        layers.first { $0.id == layer }?.isBackground == true
    }

    private func layerIndex(_ layer: UUID) -> Int {
        layers.firstIndex { $0.id == layer } ?? 0
    }

    /// The sort key of `drawOrder`: place plus z-index, then z-index, then place.
    private func rank(_ key: CelKey, z: Int? = nil) -> (Int, Int, Int) {
        let i = layerIndex(key.layer), z = z ?? celZIndex[key] ?? 0
        return (i + z, z, i)
    }

    /// Gives `key` the z-index closest to 0 that draws it between its new
    /// neighbours in `order`, or redoes the frame's z-indexes if none does.
    private mutating func place(_ key: CelKey, in order: [CelKey], at position: Int) {
        let below = position > 0 ? rank(order[position - 1]) : nil
        let above = position < order.count - 1 ? rank(order[position + 1]) : nil
        let fits = (-layers.count...layers.count).filter { z in
            let r = rank(key, z: z)
            return (below.map { $0 < r } ?? true) && (above.map { r < $0 } ?? true)
        }
        if let z = fits.min(by: { abs($0) < abs($1) }) {
            celZIndex[key] = z == 0 ? nil : z
            return
        }
        // Every cel of the frame gets the z-index that puts it at its place in
        // `order`, keeping the lowest it can so most stay at 0.
        var last: (Int, Int, Int)?
        for cel in order {
            let ci = layerIndex(cel.layer)
            var z = 0
            if let last {
                z = max(0, last.0 - ci)
                while (ci + z, z, ci) <= last { z += 1 }
            }
            celZIndex[cel] = z == 0 ? nil : z
            last = (ci + z, z, ci)
        }
    }
}
