import Foundation

/// Block operations of the timeline: moving and copying cels, frames and
/// layers, as in Aseprite's drag and drop.
/// https://www.aseprite.org/docs/move-cels/ · https://www.aseprite.org/docs/copy-cels/
extension Sprite {
    /// What a cel holds besides its key: the image, its opacity and its link group.
    struct CelContent: Equatable, Sendable {
        var image: PixelImage?
        var opacity: Double?

        static let empty = CelContent(image: nil, opacity: nil)
    }

    func content(_ key: CelKey) -> CelContent {
        CelContent(image: cels[key], opacity: celOpacity[key])
    }

    mutating func setContent(_ content: CelContent, _ key: CelKey) {
        cels[key] = content.image
        celOpacity[key] = content.image == nil ? nil : content.opacity
    }

    /// Appends empty frames until there are at least `count`.
    mutating func ensureFrames(_ count: Int) {
        let duration = frames.last?.duration ?? 100
        while frames.count < count { insertFrame(Frame(duration: duration), at: frames.count) }
    }

    /// Moves (or copies) the cels of `layerIndices` × `frameRange` by
    /// `dLayers` positions up the stack and `dFrames` to the right. The block
    /// replaces whatever was under it. Frames are added when it goes past the
    /// end. Copies on a continuous layer are linked to their originals.
    /// Returns the offsets actually applied (the block can't leave the layer stack).
    @discardableResult
    mutating func moveCels(layerIndices: [Int], frameRange: ClosedRange<Int>, dLayers: Int, dFrames: Int, copy: Bool) -> (dLayers: Int, dFrames: Int) {
        guard let low = layerIndices.min(), let high = layerIndices.max() else { return (0, 0) }
        let dl = min(max(dLayers, -low), layers.count - 1 - high)
        let df = max(dFrames, -frameRange.lowerBound)
        guard dl != 0 || df != 0 else { return (0, 0) }
        ensureFrames(frameRange.upperBound + df + 1)

        struct Item { var from: CelKey; var to: CelKey; var content: CelContent; var group: UUID?; var sameLayer: Bool }
        var items: [Item] = []
        for li in layerIndices {
            for f in frameRange where frames.indices.contains(f) {
                let from = CelKey(layer: layers[li].id, frame: frames[f].id)
                let to = CelKey(layer: layers[li + dl].id, frame: frames[f + df].id)
                items.append(Item(from: from, to: to, content: content(from), group: links[from], sameLayer: dl == 0))
            }
        }
        if !copy {
            for item in items {
                setContent(.empty, item.from)
                links[item.from] = nil
            }
        }
        for item in items {
            setContent(item.content, item.to)
            links[item.to] = nil
            guard item.sameLayer else { continue }
            if !copy {
                links[item.to] = item.group
            } else if item.content.image != nil, layers.first(where: { $0.id == item.to.layer })?.isContinuous == true {
                let group = links[item.from] ?? UUID()
                links[item.from] = group
                links[item.to] = group
            }
        }
        normalizeLinks()
        return (dl, df)
    }

    /// Moves (or copies) the frames in `range` so they start at `destination`,
    /// an insertion index into the current frames (`0...frames.count`).
    /// Returns where the frames ended up.
    @discardableResult
    mutating func moveFrames(_ range: ClosedRange<Int>, to destination: Int, copy: Bool) -> ClosedRange<Int> {
        let destination = min(max(0, destination), frames.count)
        if copy {
            let sources = Array(frames[range])
            for (offset, source) in sources.enumerated() {
                let frame = Frame(duration: source.duration)
                insertFrame(frame, at: destination + offset)
                for layer in layers {
                    let from = CelKey(layer: layer.id, frame: source.id), to = CelKey(layer: layer.id, frame: frame.id)
                    setContent(content(from), to)
                    if layer.isContinuous, cels[from] != nil {
                        let group = links[from] ?? UUID()
                        links[from] = group
                        links[to] = group
                    }
                }
            }
            normalizeLinks()
            return destination...(destination + range.count - 1)
        }
        guard destination < range.lowerBound || destination > range.upperBound + 1 else { return range }
        let block = Array(frames[range])
        frames.removeSubrange(range)
        let start = destination > range.upperBound ? destination - range.count : destination
        frames.insert(contentsOf: block, at: start)
        return start...(start + range.count - 1)
    }

    /// Moves (or copies) the layers `ids` so the block sits where the layer at
    /// `target` is (above it when copying). Returns the ids of the moved layers or the copies.
    @discardableResult
    mutating func moveLayers(_ ids: Set<UUID>, to target: Int, copy: Bool) -> [UUID] {
        let indices = layers.indices.filter { ids.contains(layers[$0].id) }
        guard let low = indices.first, let high = indices.last, layers.indices.contains(target) else { return [] }
        if copy {
            let copies = indices.map { duplicateLayer(layers[$0]) }
            layers.insert(contentsOf: copies, at: target + 1)
            return copies.map(\.id)
        }
        guard target < low || target > high else { return Array(ids) }
        let block = indices.map { layers[$0] }
        layers.removeAll { ids.contains($0.id) }
        let start = target > high ? target - block.count + 1 : target
        layers.insert(contentsOf: block, at: start)
        keepBackgroundAtBottom()
        return block.map(\.id)
    }

    /// A copy of `layer` with its cels. Links inside the layer are kept between the copies.
    private mutating func duplicateLayer(_ layer: Layer) -> Layer {
        var copy = layer
        copy.id = UUID()
        copy.name = L10n.string("%@ copy", layer.name)
        copy.isBackground = false
        var groups: [UUID: UUID] = [:]
        for frame in frames {
            let from = CelKey(layer: layer.id, frame: frame.id), to = CelKey(layer: copy.id, frame: frame.id)
            setContent(content(from), to)
            if let group = links[from] {
                links[to] = groups[group, default: UUID()]
                groups[group] = links[to]
            }
        }
        return copy
    }

    // MARK: Frame durations

    /// The duration most frames share (ties go to the earliest frame), or nil
    /// when every frame lasts the same. Frames that differ get marked in the timeline.
    var usualFrameDuration: Int? {
        guard let first = frames.first?.duration, frames.contains(where: { $0.duration != first }) else { return nil }
        var counts: [Int: Int] = [:]
        for frame in frames { counts[frame.duration, default: 0] += 1 }
        let top = counts.values.max() ?? 0
        return frames.first { counts[$0.duration] == top }?.duration
    }

    // MARK: Tag bands

    /// Tags stacked in bands (rows) so overlapping ranges don't cover each other.
    /// https://www.aseprite.org/docs/focus-tag/
    var tagBands: [(tag: FrameTag, band: Int)] {
        var bandEnds: [Int] = []
        return tags.sorted { ($0.from, $0.to) < ($1.from, $1.to) }.map { tag in
            if let band = bandEnds.firstIndex(where: { $0 < tag.from }) {
                bandEnds[band] = tag.to
                return (tag, band)
            }
            bandEnds.append(tag.to)
            return (tag, bandEnds.count - 1)
        }
    }

    var tagBandCount: Int { (tagBands.map(\.band).max() ?? -1) + 1 }
}

// MARK: - Merging layers

extension Sprite {
    /// Draws the layer at `index` onto the one below in every frame and removes it.
    mutating func mergeDown(at index: Int) {
        guard layers.indices.contains(index), index > 0 else { return }
        let upper = layers[index], lower = layers[index - 1]
        for frame in frames {
            let top = CelKey(layer: upper.id, frame: frame.id), bottom = CelKey(layer: lower.id, frame: frame.id)
            guard upper.isVisible, let image = cels[top] else { continue }
            let opacity = upper.opacity * (celOpacity[top] ?? 1)
            guard opacity > 0 else { continue }
            var base = cels[bottom] ?? PixelImage(width: width, height: height)
            // The lower cel's own opacity is baked in, or it would fade the merged pixels too.
            if let own = celOpacity[bottom], own < 1 {
                for i in base.pixels.indices { base.pixels[i].a = UInt8((Double(base.pixels[i].a) * own).rounded()) }
                celOpacity[bottom] = nil
            }
            for i in image.pixels.indices where image.pixels[i].a != 0 {
                base.pixels[i] = upper.blendMode.composite(image.pixels[i], over: base.pixels[i], opacity: opacity)
            }
            cels[bottom] = base
            // Its linked cels didn't get the upper pixels, so it isn't linked anymore.
            links[bottom] = nil
        }
        layers.remove(at: index)
        cels = cels.filter { $0.key.layer != upper.id }
        normalizeLinks()
    }

    /// Replaces all layers with one holding each frame's visible image.
    /// Returns the new layer's id.
    mutating func flatten(name: String) -> UUID {
        let background = layers.contains { $0.isBackground && $0.isVisible }
        let layer = Layer(name: background ? L10n.string("Background") : name, isBackground: background)
        var flat: [CelKey: PixelImage] = [:]
        for (index, frame) in frames.enumerated() {
            let image = composite(frameIndex: index)
            if !image.isEmpty { flat[CelKey(layer: layer.id, frame: frame.id)] = image }
        }
        // Reference layers aren't part of the image; they stay as they are (out of any group).
        layers = layers.filter(\.isReference).map { var l = $0; l.parent = nil; return l } + [layer]
        if background { layers.insert(layers.removeLast(), at: 0) }
        cels = flat
        links = [:]
        celOpacity = [:]
        return layer.id
    }
}
