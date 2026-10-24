import Foundation
import Observation

/// Onion skin options, like Aseprite's: how many frames to show on each
/// side, how strongly, and whether to tint them red (before) and blue (after).
struct OnionSkinSettings: Equatable {
    var previous = 1
    var next = 1
    var opacity = 0.35
    var tint = true
    /// Only show frames inside the active frame's tag.
    var onlyInTag = false
}

/// Editing session for one sprite: the sprite itself, the editor state
/// (active cel, tool, colors) and the undo history.
@MainActor
@Observable
final class SpriteDocument {
    let id: UUID
    var name: String { didSet { hasUnsavedChanges = true } }
    /// The sprite itself is not observed: changing pixels mid-stroke must not
    /// invalidate SwiftUI views. Views depend on `revision`, which `sprite`
    /// reads, and which is bumped once per committed change.
    @ObservationIgnored private var storage: Sprite
    var sprite: Sprite {
        _ = revision
        return storage
    }
    private(set) var revision = 0
    /// Called with the changed area while a stroke is in progress, so the
    /// canvas can redraw just that area without a SwiftUI update.
    @ObservationIgnored var onCanvasChange: ((PixelRect) -> Void)?
    private(set) var hasUnsavedChanges = false

    var activeLayerID: UUID
    var activeFrameIndex = 0
    private(set) var tool: Tool = .pencil
    private var previousTool: Tool = .pencil
    var primary: PixelColor
    var secondary: PixelColor
    var mirrorX = false
    var brushSize = 1
    var brushShape = BrushShape.square
    /// Removes the extra corner pixel in 1 px freehand strokes (Aseprite's pixel-perfect).
    var pixelPerfect = true
    var shapeFilled = false
    /// Bucket fills only the connected area; when off it replaces the color everywhere in the cel.
    var fillContiguous = true
    var showGrid = true
    var onionSkin = false
    var onionSettings = OnionSkinSettings()
    /// Playback speed multiplier (1 = the frames' own durations).
    var playbackSpeed: Double = 1
    private(set) var isPlaying = false
    /// Short feedback shown over the canvas, e.g. when drawing on a locked layer.
    var notice: String?

    private var undoStack: [Sprite] = []
    private var redoStack: [Sprite] = []
    @ObservationIgnored private var strokeStart: Sprite?
    @ObservationIgnored private var lastPoint: PixelPoint?
    @ObservationIgnored private var shapeOrigin: PixelPoint?
    /// Area the shape preview covered last time, to clear it when it moves.
    @ObservationIgnored private var shapeRect: PixelRect?
    /// Pixels plotted so far in a 1 px freehand stroke, for pixel-perfect.
    @ObservationIgnored private var strokePath: [PixelPoint] = []
    static let maxBrushSize = 8
    @ObservationIgnored private var playTask: Task<Void, Never>?
    private static let historyLimit = 100

    init(id: UUID = UUID(), name: String, sprite: Sprite) {
        self.id = id
        self.name = name
        self.storage = sprite
        self.activeLayerID = sprite.layers.last!.id
        // Start with the most saturated color, so the first stroke stands out on the checkerboard.
        let opaque = sprite.palette.filter { !$0.isTransparent }
        func chroma(_ c: PixelColor) -> Int { Int(max(c.r, c.g, c.b)) - Int(min(c.r, c.g, c.b)) }
        func luma(_ c: PixelColor) -> Int { Int(c.r) * 3 + Int(c.g) * 6 + Int(c.b) }
        self.primary = opaque.max { chroma($0) < chroma($1) } ?? .black
        self.secondary = opaque.min { luma($0) < luma($1) } ?? .white
    }

    var file: SpriteFile { SpriteFile(name: name, sprite: sprite) }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var activeLayer: Layer? { sprite.layers.first { $0.id == activeLayerID } }
    var activeFrame: Frame { sprite.frames[activeFrameIndex] }

    func markSaved() { hasUnsavedChanges = false }

    // MARK: - History

    private func changed() {
        revision &+= 1
        hasUnsavedChanges = true
    }

    private func registerUndo(_ snapshot: Sprite) {
        undoStack.append(snapshot)
        if undoStack.count > Self.historyLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// Applies a structural change as one undoable step.
    private func perform(_ change: (inout Sprite) -> Void) {
        stopPlayback()
        let before = storage
        change(&storage)
        guard storage != before else { return }
        registerUndo(before)
        fixSelection()
        changed()
    }

    func undo() {
        cancelStroke()
        guard let previous = undoStack.popLast() else { return }
        stopPlayback()
        redoStack.append(storage)
        storage = previous
        fixSelection()
        changed()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        stopPlayback()
        undoStack.append(storage)
        storage = next
        fixSelection()
        changed()
    }

    private func fixSelection() {
        if !sprite.layers.contains(where: { $0.id == activeLayerID }) {
            activeLayerID = sprite.layers.last!.id
        }
        activeFrameIndex = min(max(0, activeFrameIndex), sprite.frames.count - 1)
    }

    // MARK: - Tools and colors

    func select(_ newTool: Tool) {
        if newTool != tool { previousTool = tool }
        tool = newTool
    }

    /// Apple Pencil double tap: toggles between the eraser and the last tool.
    func toggleEraser() {
        if tool == .eraser {
            select(previousTool == .eraser ? .pencil : previousTool)
        } else {
            select(.eraser)
        }
    }

    func swapColors() {
        (primary, secondary) = (secondary, primary)
    }

    func pickColor(at p: PixelPoint) {
        let image = sprite.composite(frameIndex: activeFrameIndex)
        guard image.contains(p), !image[p].isTransparent else { return }
        primary = image[p]
    }

    // MARK: - Strokes
    //
    // While a stroke is in progress pixels change in `storage` without bumping
    // `revision`; the canvas is told which area changed through `onCanvasChange`.
    // The stroke is committed (one undo step, one SwiftUI update) when it ends.

    private var activeCelKey: CelKey { CelKey(layer: activeLayerID, frame: activeFrame.id) }

    func beginStroke(at p: PixelPoint) {
        cancelStroke()
        stopPlayback()
        if tool == .eyedropper {
            pickColor(at: p)
            return
        }
        guard let layer = activeLayer else { return }
        if !layer.isVisible { notice = L10n.string("Layer “%@” is hidden", layer.name); return }
        if layer.isLocked { notice = L10n.string("Layer “%@” is locked", layer.name); return }

        strokeStart = storage
        switch tool {
        case .bucket:
            let color = primary, contiguous = fillContiguous
            mutateActiveCel(dirty: nil) { image in
                if contiguous {
                    Raster.floodFill(&image, at: p, with: color)
                } else {
                    Raster.replaceColor(&image, at: p, with: color)
                }
            }
            endStroke()
        case .line, .rectangle, .ellipse:
            shapeOrigin = p
            shapeRect = nil
            drawShape(to: p)
        default:
            lastPoint = p
            strokePath = []
            plotFreehand([p])
        }
    }

    func continueStroke(to p: PixelPoint) {
        continueStroke(through: [p])
    }

    /// Extends the stroke through several points at once (all the Pencil
    /// samples of one touch event), redrawing the canvas only once.
    func continueStroke(through points: [PixelPoint]) {
        guard strokeStart != nil, let target = points.last else { return }
        if tool.isShape {
            drawShape(to: target)
            return
        }
        guard var last = lastPoint else { return }
        var path: [PixelPoint] = []
        for p in points where p != last {
            path.append(contentsOf: Raster.line(from: last, to: p).dropFirst())
            last = p
        }
        guard !path.isEmpty else { return }
        lastPoint = last
        plotFreehand(path)
    }

    func endStroke() {
        guard let start = strokeStart else { return }
        resetStroke()
        let key = activeCelKey
        if storage.cels[key]?.isEmpty == true { storage.cels[key] = nil }
        if start != storage { registerUndo(start) }
        changed()
    }

    /// Reverts the stroke in progress, e.g. when a finger stroke turns out to be a pinch.
    func cancelStroke() {
        guard let start = strokeStart else { return }
        resetStroke()
        storage = start
        changed()
    }

    private func resetStroke() {
        strokeStart = nil
        lastPoint = nil
        shapeOrigin = nil
        shapeRect = nil
        strokePath = []
    }

    var strokeColor: PixelColor { tool == .eraser ? .clear : primary }

    /// Area covered by stamping the brush on `points`, including its mirror.
    private func dirtyRect(for points: some Sequence<PixelPoint>) -> PixelRect? {
        let lower = -(brushSize - 1) / 2, upper = brushSize / 2
        guard var rect = PixelRect(bounding: points, lower: lower, upper: upper) else { return nil }
        if mirrorX { rect = rect.union(rect.mirrored(width: storage.width)) }
        return rect.clipped(width: storage.width, height: storage.height)
    }

    /// Stamps the brush on every point (and its mirror when symmetry is on).
    private func stamp(_ points: [PixelPoint], on image: inout PixelImage, color: PixelColor) {
        let offsets = Raster.brushOffsets(size: brushSize, shape: brushShape)
        for p in points {
            for o in offsets {
                let q = PixelPoint(x: p.x + o.x, y: p.y + o.y)
                guard image.contains(q) else { continue }
                image[q] = color
                if mirrorX { image[image.width - 1 - q.x, q.y] = color }
            }
        }
    }

    private func plotFreehand(_ points: [PixelPoint]) {
        let color = strokeColor
        let usePixelPerfect = pixelPerfect && brushSize == 1
        let original = strokeStart?.cels[activeCelKey]
        // Pixel-perfect may restore the pixel before these points, so include it.
        let dirty = dirtyRect(for: points + strokePath.suffix(2))
        mutateActiveCel(dirty: dirty) { image in
            for p in points {
                if strokePath.last == p { continue }
                stamp([p], on: &image, color: color)
                guard usePixelPerfect else { continue }
                strokePath.append(p)
                removePixelPerfectCorner(in: &image, original: original)
            }
        }
    }

    /// When the last three pixels make an L (the ends touch diagonally),
    /// the middle one is redundant: restore what was under it.
    private func removePixelPerfectCorner(in image: inout PixelImage, original: PixelImage?) {
        let n = strokePath.count
        guard n >= 3 else { return }
        let a = strokePath[n - 3], b = strokePath[n - 2], c = strokePath[n - 1]
        let isCorner = (a.x == b.x || a.y == b.y) && (c.x == b.x || c.y == b.y)
            && abs(a.x - c.x) == 1 && abs(a.y - c.y) == 1
        guard isCorner, image.contains(b) else { return }
        image[b] = original?[b] ?? .clear
        if mirrorX {
            let m = PixelPoint(x: image.width - 1 - b.x, y: b.y)
            image[m] = original?[m] ?? .clear
        }
        strokePath.remove(at: n - 2)
    }

    /// Redraws the shape from the touch-down point on top of the cel as it was
    /// when the stroke began, so dragging previews it live.
    private func drawShape(to p: PixelPoint) {
        guard let start = strokeStart, let origin = shapeOrigin else { return }
        let points: [PixelPoint]
        switch tool {
        case .line: points = Raster.line(from: origin, to: p)
        case .rectangle: points = Raster.rectangle(from: origin, to: p, filled: shapeFilled)
        case .ellipse: points = Raster.ellipse(from: origin, to: p, filled: shapeFilled)
        default: return
        }
        let key = activeCelKey
        let newRect = dirtyRect(for: points)
        // Repaint where the previous preview was, too, so it disappears.
        let dirty = [shapeRect, newRect].compactMap { $0 }.reduce(nil as PixelRect?) { $0?.union($1) ?? $1 }
        let previous = shapeRect
        shapeRect = newRect
        let color = strokeColor
        mutateActiveCel(dirty: dirty) { image in
            if let previous, let original = start.cels[key] {
                // Restore only the area the last preview touched.
                for y in previous.minY...previous.maxY {
                    for x in previous.minX...previous.maxX { image[x, y] = original[x, y] }
                }
            } else if let previous {
                for y in previous.minY...previous.maxY {
                    for x in previous.minX...previous.maxX { image[x, y] = .clear }
                }
            }
            stamp(points, on: &image, color: color)
        }
    }

    func setBrushSize(_ size: Int) {
        brushSize = min(Self.maxBrushSize, max(1, size))
    }

    /// Edits the active cel in place. During a stroke only `dirty` is redrawn
    /// on the canvas; outside a stroke it's a normal committed change.
    private func mutateActiveCel(dirty: PixelRect?, _ body: (inout PixelImage) -> Void) {
        let key = activeCelKey
        var image = storage.cels[key] ?? PixelImage(width: storage.width, height: storage.height)
        // Drop the dictionary's reference so the mutation below doesn't copy.
        storage.cels[key] = nil
        body(&image)
        storage.cels[key] = image
        if strokeStart != nil {
            if let dirty { onCanvasChange?(dirty) }
        } else {
            changed()
        }
    }

    // MARK: - Layers

    func selectCel(layer: UUID, frameIndex: Int) {
        stopPlayback()
        activeLayerID = layer
        activeFrameIndex = frameIndex
    }

    func addLayer() {
        let names = Set(sprite.layers.map(\.name))
        var n = sprite.layers.count + 1
        func layerName(_ n: Int) -> String { L10n.string("Layer %d", n) }
        while names.contains(layerName(n)) { n += 1 }
        let layer = Layer(name: layerName(n))
        let index = sprite.layers.firstIndex { $0.id == activeLayerID } ?? sprite.layers.count - 1
        perform { $0.layers.insert(layer, at: index + 1) }
        activeLayerID = layer.id
    }

    func deleteLayer(_ id: UUID) {
        guard sprite.layers.count > 1, let index = sprite.layers.firstIndex(where: { $0.id == id }) else { return }
        if id == activeLayerID {
            activeLayerID = sprite.layers[index > 0 ? index - 1 : 1].id
        }
        perform { s in
            s.layers.remove(at: index)
            s.cels = s.cels.filter { $0.key.layer != id }
        }
    }

    func toggleVisibility(_ id: UUID) {
        updateLayer(id) { $0.isVisible.toggle() }
    }

    func toggleLock(_ id: UUID) {
        updateLayer(id) { $0.isLocked.toggle() }
    }

    func renameLayer(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        updateLayer(id) { $0.name = trimmed }
    }

    func setOpacity(_ opacity: Double, layer id: UUID) {
        updateLayer(id) { $0.opacity = min(1, max(0, opacity)) }
    }

    /// Positive `offset` moves the layer up (towards the top of the stack).
    func moveLayer(_ id: UUID, by offset: Int) {
        guard let index = sprite.layers.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard sprite.layers.indices.contains(target) else { return }
        perform { $0.layers.swapAt(index, target) }
    }

    /// Moves a layer to the stack position currently held by `target` (drag and drop).
    func moveLayer(_ id: UUID, to target: UUID) {
        guard id != target,
              let from = sprite.layers.firstIndex(where: { $0.id == id }),
              let to = sprite.layers.firstIndex(where: { $0.id == target }) else { return }
        perform { s in
            let layer = s.layers.remove(at: from)
            s.layers.insert(layer, at: to)
        }
    }

    private func updateLayer(_ id: UUID, _ change: (inout Layer) -> Void) {
        guard let index = sprite.layers.firstIndex(where: { $0.id == id }) else { return }
        perform { change(&$0.layers[index]) }
    }

    // MARK: - Frames

    /// Inserts a frame after the active one. Like Aseprite's "New Frame",
    /// it duplicates the active frame unless `empty` is set.
    func addFrame(empty: Bool = false) {
        let source = activeFrame
        let frame = Frame(duration: source.duration)
        let index = activeFrameIndex
        perform { s in
            s.insertFrame(frame, at: index + 1)
            guard !empty else { return }
            for layer in s.layers {
                if let image = s.cel(layer: layer.id, frame: source.id) {
                    s.cels[CelKey(layer: layer.id, frame: frame.id)] = image
                }
            }
        }
        activeFrameIndex = index + 1
    }

    func deleteFrame(at index: Int) {
        guard sprite.frames.count > 1, sprite.frames.indices.contains(index) else { return }
        perform { $0.removeFrame(at: index) }
    }

    func moveFrame(at index: Int, by offset: Int) {
        moveFrame(from: index, to: index + offset)
    }

    func moveFrame(from source: Int, to destination: Int) {
        guard source != destination,
              sprite.frames.indices.contains(source), sprite.frames.indices.contains(destination) else { return }
        let wasActive = activeFrameIndex == source
        perform { $0.moveFrame(from: source, to: destination) }
        if wasActive { activeFrameIndex = destination }
    }

    func setDuration(_ ms: Int, frameIndex: Int) {
        guard sprite.frames.indices.contains(frameIndex) else { return }
        perform { $0.frames[frameIndex].duration = min(10_000, max(10, ms)) }
    }

    func goToFrame(_ index: Int) {
        stopPlayback()
        let count = sprite.frames.count
        activeFrameIndex = ((index % count) + count) % count
    }

    // MARK: - Tags

    /// Creates a tag on the active frame and returns it.
    @discardableResult
    func addTag() -> FrameTag {
        let index = activeFrameIndex
        let tag = FrameTag(
            name: L10n.string("Tag %d", sprite.tags.count + 1),
            from: index,
            to: index,
            color: FrameTag.colors[sprite.tags.count % FrameTag.colors.count]
        )
        perform { $0.tags.append(tag) }
        return tag
    }

    func updateTag(_ tag: FrameTag) {
        guard let index = sprite.tags.firstIndex(where: { $0.id == tag.id }) else { return }
        var tag = tag
        let last = sprite.frames.count - 1
        tag.from = min(max(0, tag.from), last)
        tag.to = min(max(tag.from, tag.to), last)
        tag.repeatCount = max(0, tag.repeatCount)
        let trimmed = tag.name.trimmingCharacters(in: .whitespaces)
        tag.name = trimmed.isEmpty ? sprite.tags[index].name : trimmed
        perform { $0.tags[index] = tag }
    }

    func deleteTag(_ id: UUID) {
        perform { $0.tags.removeAll { $0.id == id } }
    }

    var activeTag: FrameTag? { sprite.tag(containing: activeFrameIndex) }

    // MARK: - Palette

    func addToPalette(_ color: PixelColor) {
        guard !sprite.palette.contains(color) else { return }
        perform { $0.palette.append(color) }
    }

    func removeFromPalette(at index: Int) {
        guard sprite.palette.indices.contains(index) else { return }
        perform { $0.palette.remove(at: index) }
    }

    // MARK: - Playback

    func togglePlayback() {
        isPlaying ? stopPlayback() : startPlayback()
    }

    /// Plays the tag that contains the active frame (with its direction and
    /// repeat count), or every frame in a loop when the frame has no tag.
    func startPlayback() {
        guard !isPlaying else { return }
        let (cycle, repeatCount) = sprite.playbackCycle(at: activeFrameIndex)
        guard cycle.count > 1 else { return }
        cancelStroke()
        isPlaying = true
        let start = cycle.firstIndex(of: activeFrameIndex) ?? 0
        playTask = Task { [weak self] in
            var position = start
            var loops = 0
            while !Task.isCancelled {
                guard let self else { return }
                let duration = Double(self.activeFrame.duration) / max(0.1, self.playbackSpeed)
                try? await Task.sleep(for: .milliseconds(Int(duration)))
                guard !Task.isCancelled else { return }
                position += 1
                if position == cycle.count {
                    loops += 1
                    if repeatCount > 0 && loops >= repeatCount {
                        self.stopPlayback()
                        return
                    }
                    position = 0
                }
                self.activeFrameIndex = cycle[position]
            }
        }
    }

    func stopPlayback() {
        playTask?.cancel()
        playTask = nil
        isPlaying = false
    }
}
