import CoreGraphics
import Foundation
import Observation

/// One undo step: the sprite and the selection, like Aseprite (deselecting is undoable).
struct DocumentSnapshot: Equatable {
    var sprite: Sprite
    var selection: SelectionMask?
}

/// Live numbers shown while transforming.
struct TransformInfo: Equatable {
    var width = 0
    var height = 0
    var degrees = 0
}

/// What a drag on the transform box does.
enum TransformHandle: Equatable {
    case move, scale(Int), rotate, pivot
}

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

    /// Changing the active cel drops any floating pixels first, like Aseprite.
    var activeLayerID: UUID { didSet { if oldValue != activeLayerID { applyTransformIfNeeded() } } }
    var activeFrameIndex = 0 { didSet { if oldValue != activeFrameIndex { applyTransformIfNeeded() } } }
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

    // Selection
    /// Not observed (it changes on every move of a marquee drag); views use `hasSelection`.
    @ObservationIgnored private(set) var selection: SelectionMask? {
        didSet {
            if hasSelection != (selection != nil) { hasSelection = selection != nil }
            onOverlayChange?()
        }
    }
    private(set) var hasSelection = false
    @ObservationIgnored private var lastSelection: SelectionMask?
    @ObservationIgnored private var selectionDrag: (start: PixelPoint, before: SelectionMask?, moved: Bool)?
    @ObservationIgnored private var lassoPath: [PixelPoint] = []
    var selectionMode = SelectionMode.replace
    /// Magic wand options.
    var wandTolerance = 0
    var wandContiguous = true
    var wandSampleAllLayers = false
    // Timeline range selection
    var isSelectingRange = false
    var timelineRange: TimelineRange?
    @ObservationIgnored var rangeAnchor: (layer: UUID, frame: Int)?

    /// Called when the selection outline or the transform box changes.
    @ObservationIgnored var onOverlayChange: (() -> Void)?

    // Transform
    @ObservationIgnored private var floating: FloatingSelection?
    @ObservationIgnored private var floatingBase: PixelImage?
    @ObservationIgnored private var transformStart: DocumentSnapshot?
    @ObservationIgnored private var floatingDirty: PixelRect?
    @ObservationIgnored private var transformDrag: (handle: TransformHandle, start: CGPoint, box: TransformBox)?
    private(set) var isTransforming = false
    private(set) var transformInfo = TransformInfo()
    var rotationAlgorithm = RotationAlgorithm.rotSprite {
        didSet {
            guard floating != nil else { return }
            floating?.algorithm = rotationAlgorithm
            renderFloating()
        }
    }
    var keepAspect = false
    /// Snaps free rotation to 15° steps.
    var snapAngle = true
    /// The floating pixels' box, for the canvas handles.
    var transformBox: TransformBox? { floating?.box }

    private var undoStack: [DocumentSnapshot] = []
    private var redoStack: [DocumentSnapshot] = []
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

    /// Commits a change. Edits always land in the active cel, so its linked
    /// cels are brought up to date here.
    private func changed() {
        if storage.frames.indices.contains(activeFrameIndex) { storage.syncLinks(from: activeCelKey) }
        revision &+= 1
        hasUnsavedChanges = true
    }

    private func registerUndo(_ snapshot: DocumentSnapshot) {
        undoStack.append(snapshot)
        if undoStack.count > Self.historyLimit { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// Applies a structural change as one undoable step.
    private func perform(_ change: (inout Sprite) -> Void) {
        applyTransformIfNeeded()
        stopPlayback()
        let before = storage
        change(&storage)
        guard storage != before else { return }
        registerUndo(DocumentSnapshot(sprite: before, selection: selection))
        fixSelection()
        changed()
    }

    /// While transforming, undo cancels the transform.
    func undo() {
        if isTransforming { return cancelTransform() }
        cancelStroke()
        guard let previous = undoStack.popLast() else { return }
        stopPlayback()
        redoStack.append(DocumentSnapshot(sprite: storage, selection: selection))
        restore(previous)
    }

    func redo() {
        applyTransformIfNeeded()
        guard let next = redoStack.popLast() else { return }
        stopPlayback()
        undoStack.append(DocumentSnapshot(sprite: storage, selection: selection))
        restore(next)
    }

    private func restore(_ snapshot: DocumentSnapshot) {
        storage = snapshot.sprite
        selection = snapshot.selection
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
        if newTool != .move { applyTransformIfNeeded() }
        if newTool != tool { previousTool = tool }
        tool = newTool
        toolInGroup[ToolGroup.of(newTool)] = newTool
    }

    /// The last tool used in each tool rail group.
    private(set) var toolInGroup: [ToolGroup: Tool] = [:]

    func currentTool(in group: ToolGroup) -> Tool { toolInGroup[group] ?? group.tools[0] }

    /// Moves floating pixels by whole pixels (arrow keys).
    func nudgeTransform(dx: Double, dy: Double) {
        if !isTransforming { beginTransform() }
        guard var f = floating else { return }
        f.box.translate(dx: dx, dy: dy)
        floating = f
        renderFloating()
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
        if tool.isSelection {
            beginSelection(at: p)
            return
        }
        applyTransformIfNeeded()
        guard let layer = activeLayer else { return }
        if !layer.isVisible { notice = L10n.string("Layer “%@” is hidden", layer.name); return }
        if layer.isLocked { notice = L10n.string("Layer “%@” is locked", layer.name); return }

        strokeStart = storage
        switch tool {
        case .bucket:
            let color = primary, contiguous = fillContiguous, mask = selection
            mutateActiveCel(dirty: nil) { image in
                if contiguous {
                    Raster.floodFill(&image, at: p, with: color, within: mask)
                } else {
                    Raster.replaceColor(&image, at: p, with: color, within: mask)
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
        if selectionDrag != nil { return updateSelection(through: points) }
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
        if selectionDrag != nil { return finishSelection() }
        guard let start = strokeStart else { return }
        resetStroke()
        let key = activeCelKey
        if storage.cels[key]?.isEmpty == true { storage.cels[key] = nil }
        if start != storage { registerUndo(DocumentSnapshot(sprite: start, selection: selection)) }
        changed()
    }

    /// Reverts the stroke in progress, e.g. when a finger stroke turns out to be a pinch.
    func cancelStroke() {
        if let drag = selectionDrag {
            selectionDrag = nil
            selection = drag.before
            return
        }
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
    /// With a selection, only selected pixels are painted, as in Aseprite.
    private func stamp(_ points: [PixelPoint], on image: inout PixelImage, color: PixelColor) {
        let offsets = Raster.brushOffsets(size: brushSize, shape: brushShape)
        let mask = selection
        func paint(_ q: PixelPoint) {
            guard image.contains(q), mask?.contains(q) ?? true else { return }
            image[q] = color
        }
        for p in points {
            for o in offsets {
                let q = PixelPoint(x: p.x + o.x, y: p.y + o.y)
                paint(q)
                if mirrorX { paint(PixelPoint(x: image.width - 1 - q.x, y: q.y)) }
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
            s.normalizeLinks()
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
    /// In continuous layers the new cel is linked to the source cel instead of copied.
    func addFrame(empty: Bool = false) {
        let source = activeFrame
        let frame = Frame(duration: source.duration)
        let index = activeFrameIndex
        perform { s in
            s.insertFrame(frame, at: index + 1)
            guard !empty else { return }
            for layer in s.layers {
                let from = CelKey(layer: layer.id, frame: source.id), to = CelKey(layer: layer.id, frame: frame.id)
                if layer.isContinuous {
                    s.link([from, to])
                } else if let image = s.cels[from] {
                    s.cels[to] = image
                }
            }
        }
        activeFrameIndex = index + 1
    }

    func toggleContinuous(_ id: UUID) {
        updateLayer(id) { $0.isContinuous.toggle() }
    }

    func unlinkCel(layer: UUID, frameIndex: Int) {
        guard sprite.frames.indices.contains(frameIndex) else { return }
        let key = CelKey(layer: layer, frame: sprite.frames[frameIndex].id)
        perform { $0.unlink([key]) }
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

// MARK: - Selection
// https://www.aseprite.org/docs/selecting/

extension SpriteDocument {
    private var emptyMask: SelectionMask { SelectionMask(width: storage.width, height: storage.height) }

    private func beginSelection(at p: PixelPoint) {
        applyTransformIfNeeded()
        selectionDrag = (p, selection, false)
        lassoPath = [p]
        if tool == .magicWand {
            let image = wandSampleAllLayers
                ? storage.composite(frameIndex: activeFrameIndex)
                : storage.cels[activeCelKey] ?? PixelImage(width: storage.width, height: storage.height)
            applySelectionShape(SelectionMask.magicWand(in: image, at: p, tolerance: wandTolerance, contiguous: wandContiguous))
            selectionDrag?.moved = true
            finishSelection()
        } else {
            updateSelection(through: [p])
        }
    }

    private func updateSelection(through points: [PixelPoint]) {
        guard let drag = selectionDrag, let p = points.last else { return }
        if p != drag.start { selectionDrag?.moved = true }
        let shape: SelectionMask
        switch tool {
        case .selectEllipse:
            shape = .ellipse(from: drag.start, to: p, width: storage.width, height: storage.height)
        case .lasso:
            for q in points where q != lassoPath.last { lassoPath.append(q) }
            shape = .polygon(lassoPath, width: storage.width, height: storage.height)
        default:
            let rect = PixelRect(minX: min(drag.start.x, p.x), minY: min(drag.start.y, p.y), maxX: max(drag.start.x, p.x), maxY: max(drag.start.y, p.y))
            shape = .rect(rect, width: storage.width, height: storage.height)
        }
        applySelectionShape(shape)
    }

    /// Previews the new shape combined with the selection from before the drag.
    private func applySelectionShape(_ shape: SelectionMask) {
        let base = selectionDrag?.before ?? emptyMask
        let result = base.combined(with: shape, mode: selectionMode)
        selection = result.isEmpty ? nil : result
    }

    private func finishSelection() {
        guard let drag = selectionDrag else { return }
        selectionDrag = nil
        lassoPath = []
        // A tap without dragging deselects, like a click in Aseprite.
        if !drag.moved && selectionMode == .replace { selection = nil }
        guard selection != drag.before else { return }
        if drag.before != nil { lastSelection = drag.before }
        registerUndo(DocumentSnapshot(sprite: storage, selection: drag.before))
        changed()
    }

    /// Replaces the selection as one undoable step.
    private func commitSelection(_ new: SelectionMask?) {
        applyTransformIfNeeded()
        let normalized = new?.isEmpty == true ? nil : new
        guard normalized != selection else { return }
        if selection != nil { lastSelection = selection }
        registerUndo(DocumentSnapshot(sprite: storage, selection: selection))
        selection = normalized
        changed()
    }

    func selectAll() { commitSelection(SelectionMask(width: storage.width, height: storage.height, filled: true)) }
    func deselect() { commitSelection(nil) }

    func reselect() {
        guard let last = lastSelection, last.width == storage.width, last.height == storage.height else { return }
        commitSelection(last)
    }

    func invertSelection() { commitSelection((selection ?? emptyMask).inverted()) }
    func expandSelection(by amount: Int) { commitSelection(selection?.expanded(by: amount)) }
    func contractSelection(by amount: Int) { commitSelection(selection?.contracted(by: amount)) }
    func borderSelection(_ amount: Int) { commitSelection(selection?.border(amount)) }

    /// Selects the non-transparent pixels of the active cel.
    func selectLayerContent() {
        guard let cel = storage.cels[activeCelKey] else { return commitSelection(nil) }
        commitSelection(SelectionMask.opaquePixels(of: cel))
    }

    // MARK: Editing

    private var activeLayerEditable: Bool {
        guard let layer = activeLayer else { return false }
        if !layer.isVisible { notice = L10n.string("Layer “%@” is hidden", layer.name); return false }
        if layer.isLocked { notice = L10n.string("Layer “%@” is locked", layer.name); return false }
        return true
    }

    /// Clears the selected pixels of the active cel.
    func deleteSelection() {
        guard let mask = selection, activeLayerEditable else { return }
        let key = activeCelKey
        perform { s in
            guard var cel = s.cels[key] else { return }
            for i in cel.pixels.indices where mask.bits[i] { cel.pixels[i] = .clear }
            s.cels[key] = cel.isEmpty ? nil : cel
        }
    }

    /// Fills the selection (or the whole cel) with the primary color.
    func fillSelection() {
        guard activeLayerEditable else { return }
        let mask = selection, key = activeCelKey, color = primary
        let (w, h) = (storage.width, storage.height)
        perform { s in
            var cel = s.cels[key] ?? PixelImage(width: w, height: h)
            for i in cel.pixels.indices where mask?.bits[i] ?? true { cel.pixels[i] = color }
            s.cels[key] = cel
        }
    }

    /// Copies the selected pixels of the active cel (or the whole cel) to the
    /// app clipboard and, as a PNG, to the system pasteboard.
    func copy() {
        applyTransformIfNeeded()
        guard let cel = storage.cels[activeCelKey] else { return }
        let mask = selection ?? SelectionMask(width: storage.width, height: storage.height, filled: true)
        guard let bounds = mask.bounds else { return }
        var image = cel.cropped(to: bounds)
        let local = mask.cropped(to: bounds)
        for i in image.pixels.indices where !local.bits[i] { image.pixels[i] = .clear }
        PixelClipboard.store(image, origin: PixelPoint(x: bounds.minX, y: bounds.minY))
    }

    func cut() {
        copy()
        if selection != nil { deleteSelection() } else { clearActiveCel() }
    }

    private func clearActiveCel() {
        guard activeLayerEditable else { return }
        let key = activeCelKey
        perform { $0.cels[key] = nil }
    }

    /// Pastes as floating pixels on the active cel, at the copied position if it
    /// fits, otherwise centred. Images from other apps can be pasted too.
    func paste() {
        guard let (image, origin) = PixelClipboard.read(maxSize: DocumentStore.maxImportSize) else {
            notice = L10n.string("Nothing to paste")
            return
        }
        applyTransformIfNeeded()
        cancelStroke()
        stopPlayback()
        guard activeLayerEditable else { return }
        let (w, h) = (storage.width, storage.height)
        let fits = origin.x >= 0 && origin.y >= 0 && origin.x + image.width <= w && origin.y + image.height <= h
        let at = fits ? origin : PixelPoint(x: (w - image.width) / 2, y: (h - image.height) / 2)
        let key = activeCelKey
        transformStart = DocumentSnapshot(sprite: storage, selection: selection)
        floatingBase = storage.cels[key] ?? PixelImage(width: w, height: h)
        var f = FloatingSelection(celKey: key, source: image, sourceMask: SelectionMask.opaquePixels(of: image), at: at)
        f.algorithm = rotationAlgorithm
        floating = f
        floatingDirty = nil
        isTransforming = true
        if tool != .move {
            previousTool = tool
            tool = .move
        }
        renderFloating()
    }

    // MARK: Transform
    // https://www.aseprite.org/docs/transformations/

    /// Lifts the selected pixels (or the cel's content) so they can be moved,
    /// scaled, rotated and flipped. With `copy`, the original pixels stay.
    /// `wholeCanvas` lifts the full canvas when nothing is selected (flip, rotate).
    func beginTransform(copy: Bool = false, wholeCanvas: Bool = false) {
        guard !isTransforming, activeLayerEditable else { return }
        cancelStroke()
        stopPlayback()
        let key = activeCelKey
        let (w, h) = (storage.width, storage.height)
        let cel = storage.cels[key] ?? PixelImage(width: w, height: h)
        let mask: SelectionMask
        if let selection {
            mask = selection
        } else if wholeCanvas {
            mask = SelectionMask(width: w, height: h, filled: true)
        } else {
            mask = SelectionMask.opaquePixels(of: cel)
        }
        guard let bounds = mask.bounds else { return }
        var source = cel.cropped(to: bounds)
        let localMask = mask.cropped(to: bounds)
        for i in source.pixels.indices where !localMask.bits[i] { source.pixels[i] = .clear }
        var base = cel
        if !copy { for i in base.pixels.indices where mask.bits[i] { base.pixels[i] = .clear } }

        transformStart = DocumentSnapshot(sprite: storage, selection: selection)
        floatingBase = base
        var f = FloatingSelection(celKey: key, source: source, sourceMask: localMask, at: PixelPoint(x: bounds.minX, y: bounds.minY))
        f.algorithm = rotationAlgorithm
        floating = f
        floatingDirty = bounds
        isTransforming = true
        renderFloating()
    }

    /// Draws the floating pixels over the cel they were lifted from.
    private func renderFloating() {
        guard var f = floating, var cel = floatingBase else { return }
        let rendered = f.render(spriteWidth: storage.width, spriteHeight: storage.height)
        floating = f
        let o = rendered.origin
        for y in 0..<rendered.image.height {
            for x in 0..<rendered.image.width {
                let p = rendered.image[x, y]
                guard p.a != 0, rendered.mask[o.x + x, o.y + y] else { continue }
                cel[o.x + x, o.y + y] = p.blended(over: cel[o.x + x, o.y + y])
            }
        }
        storage.cels[f.celKey] = cel
        selection = rendered.mask.isEmpty ? nil : rendered.mask
        let newRect = rendered.mask.bounds
        if let dirty = [floatingDirty, newRect].compactMap({ $0 }).reduce(nil as PixelRect?, { $0?.union($1) ?? $1 }) {
            onCanvasChange?(dirty)
        }
        floatingDirty = newRect
        transformInfo = TransformInfo(
            width: Int(f.box.width.rounded()),
            height: Int(f.box.height.rounded()),
            degrees: Int((f.box.angle * 180 / .pi).rounded())
        )
        onOverlayChange?()
    }

    /// Drops the floating pixels into the cel as one undo step.
    func applyTransform() {
        guard isTransforming, let start = transformStart, let key = floating?.celKey else { return }
        floating = nil
        floatingBase = nil
        transformStart = nil
        floatingDirty = nil
        transformDrag = nil
        isTransforming = false
        if storage.cels[key]?.isEmpty == true { storage.cels[key] = nil }
        if start != DocumentSnapshot(sprite: storage, selection: selection) { registerUndo(start) }
        changed()
    }

    func cancelTransform() {
        guard isTransforming, let start = transformStart else { return }
        floating = nil
        floatingBase = nil
        transformStart = nil
        floatingDirty = nil
        transformDrag = nil
        isTransforming = false
        storage = start.sprite
        selection = start.selection
        changed()
    }

    func applyTransformIfNeeded() {
        if isTransforming { applyTransform() }
    }

    func beginTransformDrag(_ handle: TransformHandle, at point: CGPoint) {
        if !isTransforming { beginTransform() }
        guard let box = floating?.box else { return }
        transformDrag = (handle, point, box)
    }

    func continueTransformDrag(to point: CGPoint) {
        guard let drag = transformDrag, var f = floating else { return }
        var box = drag.box
        switch drag.handle {
        case .move:
            box.translate(dx: (point.x - drag.start.x).rounded(), dy: (point.y - drag.start.y).rounded())
        case .scale(let index):
            box.drag(handle: index, to: point, keepAspect: keepAspect, aspect: f.aspect)
        case .rotate:
            let from = atan2(drag.start.y - box.pivot.y, drag.start.x - box.pivot.x)
            let to = atan2(point.y - box.pivot.y, point.x - box.pivot.x)
            var angle = drag.box.angle + (to - from)
            if snapAngle {
                let step = Double.pi / 12
                angle = (angle / step).rounded() * step
            }
            box.angle = angle
        case .pivot:
            box.setPivot(CGPoint(x: (point.x * 2).rounded() / 2, y: (point.y * 2).rounded() / 2))
        }
        guard box != f.box else { return }
        f.box = box
        floating = f
        if drag.handle == .pivot { onOverlayChange?() } else { renderFloating() }
    }

    func endTransformDrag() {
        transformDrag = nil
    }

    /// Flips the selection, or the whole cel when nothing is selected.
    func flip(horizontal: Bool) {
        if !isTransforming { beginTransform(wholeCanvas: true) }
        floating?.flip(horizontal: horizontal)
        renderFloating()
    }

    /// Rotates the selection 90°, or the whole cel when nothing is selected.
    func rotate90(clockwise: Bool) {
        if !isTransforming { beginTransform(wholeCanvas: true) }
        floating?.rotate90(clockwise: clockwise)
        renderFloating()
    }

    // MARK: Canvas

    private func performCanvasChange(_ change: (inout Sprite) -> Void) {
        applyTransformIfNeeded()
        stopPlayback()
        let before = DocumentSnapshot(sprite: storage, selection: selection)
        change(&storage)
        guard storage != before.sprite else { return }
        selection = nil
        registerUndo(before)
        changed()
    }

    /// Crops the canvas to the selection's bounds.
    func cropToSelection() {
        applyTransformIfNeeded()
        guard let bounds = selection?.bounds else { return }
        performCanvasChange { $0.crop(to: bounds) }
    }

    /// Crops the canvas to the non-transparent content of all cels.
    func trimCanvas() {
        guard let bounds = storage.contentBounds else { return }
        performCanvasChange { $0.crop(to: bounds) }
    }

    func rotateCanvas(clockwise: Bool) { performCanvasChange { $0.rotateCanvas(clockwise: clockwise) } }

    func rotateCanvas180() {
        performCanvasChange { s in
            s.rotateCanvas(clockwise: true)
            s.rotateCanvas(clockwise: true)
        }
    }

    func flipCanvas(horizontal: Bool) { performCanvasChange { $0.flipCanvas(horizontal: horizontal) } }
}

// MARK: - Timeline ranges

/// A block of cels selected in the timeline: some layers × a run of frames.
struct TimelineRange: Equatable {
    var layers: Set<UUID>
    var frames: ClosedRange<Int>
}

extension SpriteDocument {
    /// Tap on a cel while selecting: the first tap anchors, the next ones
    /// extend the block from the anchor to the tapped cel.
    func extendRange(layer: UUID, frameIndex: Int) {
        guard let anchor = rangeAnchor, timelineRange != nil else {
            rangeAnchor = (layer, frameIndex)
            timelineRange = TimelineRange(layers: [layer], frames: frameIndex...frameIndex)
            return
        }
        let ids = sprite.layers.map(\.id)
        guard let a = ids.firstIndex(of: anchor.layer), let b = ids.firstIndex(of: layer) else { return }
        timelineRange = TimelineRange(
            layers: Set(ids[min(a, b)...max(a, b)]),
            frames: min(anchor.frame, frameIndex)...max(anchor.frame, frameIndex)
        )
    }

    /// Tap on a frame number while selecting: whole columns, every layer.
    func extendRange(frameIndex: Int) {
        let all = Set(sprite.layers.map(\.id))
        let start = timelineRange.map { _ in rangeAnchor?.frame ?? frameIndex } ?? frameIndex
        if timelineRange == nil { rangeAnchor = (sprite.layers.last!.id, frameIndex) }
        timelineRange = TimelineRange(layers: all, frames: min(start, frameIndex)...max(start, frameIndex))
    }

    func endRangeSelection() {
        isSelectingRange = false
        timelineRange = nil
        rangeAnchor = nil
    }

    private func rangeKeys(_ range: TimelineRange) -> [[CelKey]] {
        sprite.layers.filter { range.layers.contains($0.id) }.map { layer in
            range.frames.compactMap { f in
                sprite.frames.indices.contains(f) ? CelKey(layer: layer.id, frame: sprite.frames[f].id) : nil
            }
        }
    }

    /// Links the cels of each selected layer to the cel in the first selected frame.
    func linkRange() {
        guard let range = timelineRange else { return }
        let rows = rangeKeys(range)
        perform { s in for row in rows { s.link(row) } }
    }

    func unlinkRange() {
        guard let range = timelineRange else { return }
        let keys = rangeKeys(range).flatMap { $0 }
        perform { $0.unlink(keys) }
    }

    /// Empties the selected cels.
    func clearRange() {
        guard let range = timelineRange else { return }
        let keys = rangeKeys(range).flatMap { $0 }
        perform { s in
            for key in keys { s.cels[key] = nil }
            s.unlink(keys)
        }
    }

    /// Deletes the selected frames from every layer (at least one frame stays).
    func deleteRangeFrames() {
        guard let range = timelineRange, range.frames.count < sprite.frames.count else {
            notice = L10n.string("A sprite needs at least one frame")
            return
        }
        perform { s in
            for index in range.frames.reversed() where s.frames.indices.contains(index) { s.removeFrame(at: index) }
        }
        activeFrameIndex = min(range.frames.lowerBound, sprite.frames.count - 1)
        endRangeSelection()
    }

    /// Inserts copies of the selected frames right after them.
    func duplicateRangeFrames() {
        guard let range = timelineRange else { return }
        let sources = range.frames.compactMap { sprite.frames.indices.contains($0) ? sprite.frames[$0] : nil }
        perform { s in
            var insertAt = range.frames.upperBound + 1
            for source in sources {
                let frame = Frame(duration: source.duration)
                s.insertFrame(frame, at: insertAt)
                for layer in s.layers {
                    if let image = s.cel(layer: layer.id, frame: source.id) {
                        s.cels[CelKey(layer: layer.id, frame: frame.id)] = image
                    }
                }
                insertAt += 1
            }
        }
        let count = range.frames.count
        timelineRange = TimelineRange(layers: Set(sprite.layers.map(\.id)), frames: (range.frames.upperBound + 1)...(range.frames.upperBound + count))
        rangeAnchor = (sprite.layers.last!.id, range.frames.upperBound + 1)
    }

    /// Reverses the order of the selected frames (Aseprite's Frame > Reverse Frames).
    func reverseRangeFrames() {
        guard let range = timelineRange, range.frames.count > 1 else { return }
        perform { s in
            let reversed = Array(s.frames[range.frames].reversed())
            s.frames.replaceSubrange(range.frames, with: reversed)
        }
    }
}
