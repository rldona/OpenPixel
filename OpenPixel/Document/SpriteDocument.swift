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
    /// The canvas view that receives `onCanvasChange` and `onOverlayChange`.
    @ObservationIgnored weak var canvasOwner: AnyObject?
    private(set) var hasUnsavedChanges = false

    /// Changing the active cel drops any floating pixels first, like Aseprite.
    var activeLayerID: UUID {
        willSet { if newValue != activeLayerID { finishPendingShape() } }
        didSet { if oldValue != activeLayerID { applyTransformIfNeeded() } }
    }
    var activeFrameIndex = 0 {
        willSet { if newValue != activeFrameIndex { finishPendingShape() } }
        didSet { if oldValue != activeFrameIndex { applyTransformIfNeeded() } }
    }
    private(set) var tool: Tool = .pencil
    private var previousTool: Tool = .pencil
    var primary: PixelColor
    var secondary: PixelColor
    var symmetry = Symmetry()
    var brushSize = 1
    var brushShape = BrushShape.square
    /// Removes the extra corner pixel in 1 px freehand strokes (Aseprite's pixel-perfect).
    /// Off by default: it removes corner pixels, which trades control for
    /// smoother 1 px lines. The choice is remembered across sprites.
    var pixelPerfect = UserDefaults.standard.bool(forKey: "pixelPerfect") {
        didSet { UserDefaults.standard.set(pixelPerfect, forKey: "pixelPerfect") }
    }
    var shapeFilled = false
    /// Rounded corners for the rectangle tool, in pixels.
    var cornerRadius = 0
    static let maxCornerRadius = 32
    /// How the tool's color combines with the pixels under it.
    var ink = Ink.simple
    /// Tool opacity, 0...255 as in Aseprite.
    var toolOpacity = 255
    /// Which way the shading ink walks the palette.
    var shadeDirection = ShadeDirection.forward
    /// Apple Pencil pressure changes the brush size and/or the opacity.
    var pressureSize = UserDefaults.standard.bool(forKey: "pressureSize") {
        didSet { UserDefaults.standard.set(pressureSize, forKey: "pressureSize") }
    }
    var pressureOpacity = UserDefaults.standard.bool(forKey: "pressureOpacity") {
        didSet { UserDefaults.standard.set(pressureOpacity, forKey: "pressureOpacity") }
    }
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
    /// Marquee and lasso selections shrink to the drawn pixels inside them.
    var selectionFitsContent = true
    /// Edits on the selection (move, transform, delete, fill) change every
    /// frame, not just the one on screen.
    var selectionAllFrames = false
    /// Layers a marquee caught besides the active one: moving or transforming
    /// the selection changes them too. Nil when the selection is one layer's.
    @ObservationIgnored private(set) var selectionLayers: Set<UUID>?
    /// The shape being dragged, before it's combined with the previous selection.
    @ObservationIgnored private var dragShape: SelectionMask?
    // Timeline range selection
    var isSelectingRange = false
    var timelineRange: TimelineRange?
    /// The Replace Color sheet is open (Edit > Replace Color, ⇧R).
    var isReplacingColor = false
    /// Text tool settings, shared by every sprite while the app runs.
    var textStyle = TextStyle()
    /// Where the text tool was tapped; set while the text is being typed.
    var textAnchor: PixelPoint?
    /// Other cels of the timeline range that follow the floating transform.
    /// Only the active cel shows it live; the rest change when it's applied, as in Aseprite.
    @ObservationIgnored private var rangeFloating: [RangeFloating] = []
    /// How many other cels the transform in progress will also change.
    private(set) var transformExtraCels = 0
    /// The tool to come back to when the floating text is applied or cancelled.
    @ObservationIgnored private var toolAfterTransform: Tool?
    /// Dragging a selected block copies it instead of moving it.
    var dragCopies = false
    /// The tag band (row) the timeline focuses; playback stays inside its tags.
    var focusedTagBand: Int?
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
    /// How strongly each pixel has been painted in the current stroke (0...255).
    /// Inks are applied to the cel as it was when the stroke began, so going
    /// over the same pixel twice in one stroke doesn't build up opacity or shading.
    @ObservationIgnored private var strokeCoverage: [UInt8] = []
    @ObservationIgnored private var strokePressure: Double = 1
    /// The contour tool's path, filled when the stroke ends.
    @ObservationIgnored private var contourPath: [PixelPoint] = []
    /// The curve ([start, end, control 1, control 2]) or the polygon's corners
    /// while they're built over several touches.
    @ObservationIgnored private var pendingShape: [PixelPoint] = []
    @ObservationIgnored private var pendingBeforeDrag: [PixelPoint] = []
    @ObservationIgnored private var pendingDragging = false
    /// 0 when nothing is pending. A curve is at 1 while its line is drawn and
    /// at 2 and 3 while each end is bent; a polygon stays at 1.
    private(set) var pendingShapeStage = 0
    var isBuildingShape: Bool { pendingShapeStage != 0 }
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
        if isBuildingShape { return cancelPendingShape() }
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
        // Undoing an edit keeps the selection's layers; a different selection drops them.
        if snapshot.selection != selection { selectionLayers = nil }
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
        if newTool != tool { finishPendingShape() }
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

    /// `pressure` is the Apple Pencil's force, 0...1 (1 for fingers).
    func beginStroke(at p: PixelPoint, pressure: Double = 1) {
        if isBuildingShape {
            if tool.buildsOverTouches { return continuePendingShape(at: p) }
            finishPendingShape()
        }
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
        if tool == .text {
            textAnchor = p
            return
        }

        strokeStart = storage
        strokeCoverage = [UInt8](repeating: 0, count: storage.width * storage.height)
        strokePressure = pressure
        switch tool {
        case .bucket:
            fill(at: p)
            endStroke()
        case .line, .rectangle, .ellipse:
            shapeOrigin = p
            shapeRect = nil
            drawShape(to: p)
        case .curve, .polygon:
            pendingShape = tool == .curve ? [p, p, p, p] : [p]
            pendingBeforeDrag = []
            pendingDragging = true
            pendingShapeStage = 1
            redrawPendingShape()
        default:
            lastPoint = p
            strokePath = []
            contourPath = [p]
            plotFreehand([p], pressures: [pressure])
        }
    }

    func continueStroke(to p: PixelPoint, pressure: Double = 1) {
        continueStroke(through: [p], pressures: [pressure])
    }

    /// Extends the stroke through several points at once (all the Pencil
    /// samples of one touch event), redrawing the canvas only once.
    func continueStroke(through points: [PixelPoint], pressures: [Double]? = nil) {
        if selectionDrag != nil { return updateSelection(through: points) }
        guard strokeStart != nil, let target = points.last else { return }
        if pendingDragging {
            movePendingPoint(to: target)
            return
        }
        if tool.isShape {
            drawShape(to: target)
            return
        }
        guard var last = lastPoint else { return }
        var path: [PixelPoint] = []
        var pathPressures: [Double] = []
        for (n, p) in points.enumerated() where p != last {
            let segment = Raster.line(from: last, to: p).dropFirst()
            path.append(contentsOf: segment)
            // Ease the pressure along the segment so a fast stroke doesn't step.
            let from = strokePressure, to = pressures?[n] ?? 1
            for k in 1...segment.count { pathPressures.append(from + (to - from) * Double(k) / Double(segment.count)) }
            strokePressure = to
            last = p
        }
        guard !path.isEmpty else { return }
        lastPoint = last
        if tool == .contour { contourPath += path }
        plotFreehand(path, pressures: pathPressures)
    }

    func endStroke() {
        if selectionDrag != nil { return finishSelection() }
        if isBuildingShape {
            pendingDragging = false
            if tool == .curve {
                pendingShapeStage += 1
                if pendingShapeStage > 3 { finishPendingShape() }
            }
            return
        }
        if tool == .contour, strokeStart != nil {
            // Replace the outline drawn so far with the filled shape.
            shapeRect = dirtyRect(for: contourPath)
            drawPreview(Raster.polygon(contourPath, filled: true))
        }
        commitStroke()
    }

    /// One undo step for everything the stroke changed.
    private func commitStroke() {
        guard let start = strokeStart else { return }
        resetStroke()
        let key = activeCelKey
        if storage.cels[key]?.isEmpty == true { storage.cels[key] = nil }
        if start != storage { registerUndo(DocumentSnapshot(sprite: start, selection: selection)) }
        changed()
    }

    /// Reverts the stroke in progress, e.g. when a finger stroke turns out to be
    /// a pinch. While a curve or polygon is being built only the drag is undone.
    func cancelStroke() {
        if let drag = selectionDrag {
            selectionDrag = nil
            selection = drag.before
            return
        }
        if isBuildingShape {
            guard pendingDragging else { return }
            pendingDragging = false
            guard !pendingBeforeDrag.isEmpty else { return cancelPendingShape() }
            pendingShape = pendingBeforeDrag
            return redrawPendingShape()
        }
        revertStroke()
    }

    private func revertStroke() {
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
        strokeCoverage = []
        strokePressure = 1
        contourPath = []
    }

    // MARK: Curves and polygons

    private func continuePendingShape(at p: PixelPoint) {
        pendingBeforeDrag = pendingShape
        if tool == .polygon, pendingShape.count >= 3, let first = pendingShape.first,
           max(abs(first.x - p.x), abs(first.y - p.y)) <= 1 {
            // Tapping the first corner closes the polygon.
            return finishPendingShape()
        }
        pendingDragging = true
        if tool == .polygon { pendingShape.append(p) }
        movePendingPoint(to: p)
    }

    /// The point the current drag holds: the curve's end or a control point,
    /// or the polygon's newest corner.
    private func movePendingPoint(to p: PixelPoint) {
        if tool == .polygon {
            pendingShape[pendingShape.count - 1] = p
        } else {
            switch pendingShapeStage {
            case 1: pendingShape[1] = p
            // The first bend moves both control points, so it bends like an arc;
            // the second one moves only the end's control point.
            case 2: pendingShape[2] = p; pendingShape[3] = p
            default: pendingShape[3] = p
            }
        }
        redrawPendingShape()
    }

    private func redrawPendingShape() {
        let s = pendingShape
        switch tool {
        case .curve where s.count == 4: drawPreview(Raster.curve(from: s[0], s[2], s[3], to: s[1]))
        case .polygon where !s.isEmpty: drawPreview(Raster.polygon(s, filled: true))
        default: break
        }
        onOverlayChange?()
    }

    /// Keeps the curve or polygon as it is now, as one undo step.
    func finishPendingShape() {
        guard isBuildingShape else { return }
        pendingShape = []
        pendingBeforeDrag = []
        pendingDragging = false
        pendingShapeStage = 0
        commitStroke()
        onOverlayChange?()
    }

    func cancelPendingShape() {
        guard isBuildingShape else { return }
        pendingShape = []
        pendingBeforeDrag = []
        pendingDragging = false
        pendingShapeStage = 0
        revertStroke()
        onOverlayChange?()
    }

    /// Points the canvas marks while a curve or polygon is being built, and
    /// the lines from each end of the curve to its control point.
    var shapeGuides: (handles: [PixelPoint], lines: [(PixelPoint, PixelPoint)]) {
        guard isBuildingShape else { return ([], []) }
        let s = pendingShape
        if tool == .curve, s.count == 4 {
            return pendingShapeStage == 1 ? ([s[0], s[1]], []) : (s, [(s[0], s[2]), (s[1], s[3])])
        }
        return (s, [])
    }

    var strokeColor: PixelColor { tool == .eraser ? eraseColor : primary }

    /// What erasing leaves behind: transparency, or on the background layer
    /// the secondary color, as in Aseprite.
    var eraseColor: PixelColor {
        guard activeLayer?.isBackground == true else { return .clear }
        var color = secondary
        color.a = 255
        return color
    }

    /// Area covered by stamping the brush on `points`, including its mirror.
    /// Contours and polygons are filled shapes; they don't use the brush.
    private var effectiveBrushSize: Int { tool.usesBrush ? brushSize : 1 }

    private func dirtyRect(for points: some Sequence<PixelPoint>) -> PixelRect? {
        let brushSize = effectiveBrushSize
        let lower = -(brushSize - 1) / 2, upper = brushSize / 2
        guard var rect = PixelRect(bounding: points, lower: lower, upper: upper) else { return nil }
        rect = symmetry.covering(rect, width: storage.width, height: storage.height)
        return rect.clipped(width: storage.width, height: storage.height)
    }

    /// The ink a stroke uses: the eraser always erases.
    private var strokeInk: Ink { tool == .eraser ? .simple : ink }

    /// Stamps the brush on every point (and its mirror when symmetry is on).
    /// With a selection, only selected pixels are painted, as in Aseprite.
    /// `pressures` (0...1, one per point) scale the size and opacity when
    /// the pressure dynamics are on.
    private func stamp(_ points: [PixelPoint], pressures: [Double]? = nil, on image: inout PixelImage, color: PixelColor) {
        var offsetsBySize: [Int: [PixelPoint]] = [:]
        func offsets(_ size: Int) -> [PixelPoint] {
            if let cached = offsetsBySize[size] { return cached }
            let o = Raster.brushOffsets(size: size, shape: brushShape)
            offsetsBySize[size] = o
            return o
        }
        var painter = makePainter(color: color)
        defer { strokeCoverage = painter.coverage }
        let brushSize = effectiveBrushSize
        for (n, p) in points.enumerated() {
            let pressure = pressures?[n] ?? 1
            let size = pressureSize ? 1 + Int((Double(brushSize - 1) * pressure).rounded()) : brushSize
            let alpha = pressureOpacity ? Double(toolOpacity) * pressure : Double(toolOpacity)
            let a = UInt8(max(1, min(255, alpha.rounded())))
            for o in offsets(size) {
                let q = PixelPoint(x: p.x + o.x, y: p.y + o.y)
                painter.paint(q, alpha: a, on: &image)
                for m in symmetry.images(of: q, width: image.width, height: image.height) { painter.paint(m, alpha: a, on: &image) }
            }
        }
    }

    /// Everything a stroke needs to paint one pixel, taken out of the
    /// document so the inner loop doesn't go through observation.
    private func makePainter(color: PixelColor) -> Painter {
        let w = storage.width, h = storage.height
        var coverage = strokeCoverage
        strokeCoverage = []
        if coverage.count != w * h { coverage = [UInt8](repeating: 0, count: w * h) }
        return Painter(
            ink: strokeInk, color: color, original: strokeStart?.cels[activeCelKey], mask: selection,
            ramp: storage.palette.filter { !$0.isTransparent }, direction: shadeDirection, coverage: coverage
        )
    }

    private func plotFreehand(_ points: [PixelPoint], pressures: [Double]? = nil) {
        let color = strokeColor
        let usePixelPerfect = pixelPerfect && brushSize == 1 && (tool == .pencil || tool == .eraser)
        let original = strokeStart?.cels[activeCelKey]
        // Pixel-perfect may restore the pixel before these points, so include it.
        let dirty = dirtyRect(for: points + strokePath.suffix(2))
        mutateActiveCel(dirty: dirty) { image in
            for (n, p) in points.enumerated() {
                if strokePath.last == p { continue }
                stamp([p], pressures: pressures.map { [$0[n]] }, on: &image, color: color)
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
        // A pixel the stroke already went through elsewhere stays: removing it
        // would open a hole where the line crosses or doubles back on itself.
        guard isCorner, image.contains(b), !strokePath[..<(n - 3)].contains(b) else { return }
        func restore(_ q: PixelPoint) {
            image[q] = original?[q] ?? .clear
            if strokeCoverage.indices.contains(q.y * image.width + q.x) { strokeCoverage[q.y * image.width + q.x] = 0 }
        }
        restore(b)
        for m in symmetry.images(of: b, width: image.width, height: image.height) where image.contains(m) { restore(m) }
        strokePath.remove(at: n - 2)
    }

    private func drawShape(to p: PixelPoint) {
        guard let origin = shapeOrigin else { return }
        switch tool {
        case .line: drawPreview(Raster.line(from: origin, to: p))
        case .rectangle: drawPreview(Raster.rectangle(from: origin, to: p, filled: shapeFilled, radius: cornerRadius))
        case .ellipse: drawPreview(Raster.ellipse(from: origin, to: p, filled: shapeFilled))
        default: return
        }
    }

    /// Redraws a shape on top of the cel as it was when the stroke began, so
    /// dragging previews it live.
    private func drawPreview(_ points: [PixelPoint]) {
        guard let start = strokeStart else { return }
        let key = activeCelKey
        let newRect = dirtyRect(for: points)
        // Repaint where the previous preview was, too, so it disappears.
        let dirty = [shapeRect, newRect].compactMap { $0 }.reduce(nil as PixelRect?) { $0?.union($1) ?? $1 }
        let previous = shapeRect
        shapeRect = newRect
        let color = strokeColor
        mutateActiveCel(dirty: dirty) { image in
            if let previous {
                // Restore only the area the last preview touched.
                let original = start.cels[key]
                for y in previous.minY...previous.maxY {
                    for x in previous.minX...previous.maxX {
                        image[x, y] = original?[x, y] ?? .clear
                        strokeCoverage[y * image.width + x] = 0
                    }
                }
            }
            stamp(points, on: &image, color: color)
        }
    }

    /// Paint bucket: paints the area it reaches with the ink and opacity.
    private func fill(at p: PixelPoint) {
        let cel = storage.cels[activeCelKey] ?? PixelImage(width: storage.width, height: storage.height)
        let region = Raster.fillRegion(in: cel, at: p, contiguous: fillContiguous, within: selection)
        let color = primary, alpha = UInt8(max(1, min(255, toolOpacity)))
        mutateActiveCel(dirty: nil) { image in
            var painter = makePainter(color: color)
            for i in region.bits.indices where region.bits[i] {
                painter.paint(PixelPoint(x: i % image.width, y: i / image.width), alpha: alpha, on: &image)
            }
        }
    }

    /// Moves a symmetry axis to `position2` (in half pixels), e.g. by dragging it on the canvas.
    func moveSymmetryAxis(vertical: Bool, to position2: Int) {
        if vertical {
            symmetry.axisY2 = min(2 * storage.height - 1, max(1, position2))
        } else {
            symmetry.axisX2 = min(2 * storage.width - 1, max(1, position2))
        }
    }

    func centerSymmetryAxes() {
        symmetry.axisX2 = nil
        symmetry.axisY2 = nil
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

    /// The background layer is always opaque.
    func setOpacity(_ opacity: Double, layer id: UUID) {
        updateLayer(id) { if !$0.isBackground { $0.opacity = min(1, max(0, opacity)) } }
    }

    // Header buttons: one tap for every layer (Aseprite's timeline header).

    /// Shows every layer, or hides them all when they're all visible.
    func toggleAllVisibility() {
        let show = sprite.layers.contains { !$0.isVisible }
        perform { s in for i in s.layers.indices { s.layers[i].isVisible = show } }
    }

    func toggleAllLocks() {
        let lock = sprite.layers.contains { !$0.isLocked }
        perform { s in for i in s.layers.indices { s.layers[i].isLocked = lock } }
    }

    func toggleAllContinuous() {
        let on = sprite.layers.contains { !$0.isContinuous }
        perform { s in for i in s.layers.indices { s.layers[i].isContinuous = on } }
    }

    /// Layer > Convert To > Background: transparent pixels take the secondary
    /// color, every frame gets a cel and the layer goes to the bottom.
    func convertToBackground(_ id: UUID) {
        guard !sprite.layers.contains(where: \.isBackground) else {
            notice = L10n.string("The sprite already has a background layer")
            return
        }
        guard let index = sprite.layers.firstIndex(where: { $0.id == id }) else { return }
        var fill = secondary
        fill.a = 255
        let (w, h) = (storage.width, storage.height)
        perform { s in
            for frame in s.frames {
                let key = CelKey(layer: id, frame: frame.id)
                var cel = PixelImage(width: w, height: h, fill: fill)
                if let image = s.cels[key] {
                    let opacity = s.layers[index].opacity * (s.celOpacity[key] ?? 1)
                    for i in cel.pixels.indices where image.pixels[i].a != 0 {
                        cel.pixels[i] = image.pixels[i].blended(over: fill, opacity: opacity)
                    }
                }
                s.cels[key] = cel
                s.celOpacity[key] = nil
            }
            s.layers[index].isBackground = true
            s.layers[index].opacity = 1
            s.keepBackgroundAtBottom()
        }
    }

    /// Layer > Convert To > Layer: the background becomes a regular transparent layer.
    func convertToLayer(_ id: UUID) {
        updateLayer(id) { $0.isBackground = false }
    }

    /// Positive `offset` moves the layer up (towards the top of the stack).
    func moveLayer(_ id: UUID, by offset: Int) {
        guard let index = sprite.layers.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard sprite.layers.indices.contains(target) else { return }
        perform { s in
            s.layers.swapAt(index, target)
            s.keepBackgroundAtBottom()
        }
    }

    /// Moves a layer to the stack position currently held by `target` (drag and drop).
    func moveLayer(_ id: UUID, to target: UUID) {
        guard id != target,
              let from = sprite.layers.firstIndex(where: { $0.id == id }),
              let to = sprite.layers.firstIndex(where: { $0.id == target }) else { return }
        perform { s in
            let layer = s.layers.remove(at: from)
            s.layers.insert(layer, at: to)
            s.keepBackgroundAtBottom()
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

    /// Aseprite stores durations as 16-bit milliseconds.
    static let maxFrameDuration = 65_535

    func setDuration(_ ms: Int, frameIndex: Int) {
        guard sprite.frames.indices.contains(frameIndex) else { return }
        perform { $0.frames[frameIndex].duration = min(Self.maxFrameDuration, max(10, ms)) }
    }

    func goToFrame(_ index: Int) {
        stopPlayback()
        let count = sprite.frames.count
        activeFrameIndex = ((index % count) + count) % count
    }

    // MARK: - Tags

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

    /// Replaces the whole palette (a preset, a file, the sprite's colors). Pixels don't change.
    func setPalette(_ colors: [PixelColor]) {
        guard !colors.isEmpty else { return }
        perform { $0.palette = Array(colors.prefix(PaletteFile.maxColors)) }
    }

    func setPaletteColor(_ color: PixelColor, at index: Int) {
        guard sprite.palette.indices.contains(index) else { return }
        perform { $0.palette[index] = color }
    }

    func removePaletteColors(_ range: ClosedRange<Int>) {
        guard sprite.palette.indices.contains(range.upperBound), range.count < sprite.palette.count else {
            notice = L10n.string("A palette needs at least one color")
            return
        }
        perform { $0.palette.removeSubrange(range) }
    }

    /// Inserts copies of a run of entries right after it.
    func duplicatePaletteColors(_ range: ClosedRange<Int>) {
        guard sprite.palette.indices.contains(range.upperBound) else { return }
        perform { s in s.palette.insert(contentsOf: s.palette[range], at: range.upperBound + 1) }
    }

    @discardableResult
    func movePaletteColors(_ range: ClosedRange<Int>, to destination: Int) -> ClosedRange<Int> {
        var placed = range
        perform { placed = PaletteEditing.move(&$0.palette, range, to: destination) }
        return placed
    }

    func paletteGradient(_ range: ClosedRange<Int>) { perform { PaletteEditing.gradient(&$0.palette, range) } }
    func reversePalette(_ range: ClosedRange<Int>) { perform { PaletteEditing.reverse(&$0.palette, range) } }

    func sortPalette(_ range: ClosedRange<Int>, by order: PaletteSort, descending: Bool = false) {
        perform { PaletteEditing.sort(&$0.palette, range, by: order, descending: descending) }
    }

    /// Aseprite's "Palette from sprite": the colors the sprite actually uses.
    func paletteFromSprite() {
        let colors = Palette.colors(in: sprite)
        guard !colors.isEmpty else {
            notice = L10n.string("The sprite has no colors yet")
            return
        }
        setPalette(colors)
    }

    /// Where `color` is in the palette, if it is.
    func paletteIndex(of color: PixelColor) -> Int? { sprite.palette.firstIndex(of: color) }

    // MARK: - Replace color

    /// Edit > Replace Color: pixels within `tolerance` of `from` become `to`,
    /// in the active cel or in every cel, inside the selection if there is one.
    /// Locked layers are left alone. Returns how many pixels changed (linked cels count once each).
    @discardableResult
    func replaceColor(_ from: PixelColor, with to: PixelColor, tolerance: Int, everyCel: Bool) -> Int {
        applyTransformIfNeeded()
        let mask = selection
        let editable = Set(sprite.layers.filter { !$0.isLocked }.map(\.id))
        let keys = everyCel ? sprite.cels.keys.filter { editable.contains($0.layer) } : (editable.contains(activeLayerID) ? [activeCelKey] : [])
        guard !keys.isEmpty else {
            notice = L10n.string("The layer is locked")
            return 0
        }
        var changedPixels = 0
        perform { s in
            for key in keys {
                guard var cel = s.cels[key] else { continue }
                var touched = false
                for i in cel.pixels.indices where (mask?.bits[i] ?? true) && cel.pixels[i].matches(from, tolerance: tolerance) && cel.pixels[i] != to {
                    cel.pixels[i] = to.a == 0 ? .clear : to
                    touched = true
                    changedPixels += 1
                }
                if touched { s.cels[key] = cel.isEmpty ? nil : cel }
            }
            s.normalizeLinks()
        }
        return changedPixels
    }

    // MARK: - Playback

    func togglePlayback() {
        isPlaying ? stopPlayback() : startPlayback()
    }

    /// Plays the tag that contains the active frame (with its direction and
    /// repeat count), or every frame in a loop when the frame has no tag.
    func startPlayback() {
        guard !isPlaying else { return }
        let band = focusedTagBand.flatMap { $0 < sprite.tagBandCount ? $0 : nil }
        let (cycle, repeatCount) = sprite.playbackCycle(at: activeFrameIndex, band: band)
        guard cycle.count > 1 else { return }
        cancelStroke()
        isPlaying = true
        let start = cycle.firstIndex(of: activeFrameIndex) ?? 0
        activeFrameIndex = cycle[start]
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
        dragShape = shape
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
        let shape = dragShape
        selectionDrag = nil
        dragShape = nil
        lassoPath = []
        let base = drag.before ?? emptyMask
        if !drag.moved && tool != .magicWand {
            // A tap picks the element under it: the content of the topmost layer
            // with a pixel there. On empty canvas it deselects, like Aseprite.
            selectionLayers = nil
            if let element = element(at: drag.start) {
                activeLayerID = element.layer
                if timelineRange != nil { endRangeSelection() }
                let result = base.combined(with: element.mask, mode: selectionMode)
                selection = result.isEmpty ? nil : result
            } else if selectionMode == .replace {
                selection = nil
            }
        } else if drag.moved, tool != .magicWand, let shape {
            // A marquee over several layers takes all of them, not just the active one.
            let caught = layersWithContent(in: shape)
            if selectionFitsContent, let fitted = fittedToContent(shape, layers: caught) {
                selection = base.combined(with: fitted, mode: selectionMode)
            }
            var layers = Set(caught.map(\.id))
            if selectionMode == .add, let previous = selectionLayers { layers.formUnion(previous) }
            if selectionMode == .replace || selectionMode == .add {
                layers.insert(activeLayerID)
                selectionLayers = layers.count > 1 && timelineRange == nil ? layers : nil
            }
        }
        guard selection != drag.before else { return }
        if drag.before != nil { lastSelection = drag.before }
        registerUndo(DocumentSnapshot(sprite: storage, selection: drag.before))
        changed()
    }

    /// The topmost visible, unlocked layer with a pixel at `p` in the active
    /// frame, and all its pixels there. The background layer is skipped: it covers everything.
    private func element(at p: PixelPoint) -> (layer: UUID, mask: SelectionMask)? {
        let frame = activeFrame.id
        for layer in storage.layers.reversed() where layer.isVisible && !layer.isBackground && !layer.isLocked {
            guard let cel = storage.cel(layer: layer.id, frame: frame), cel.contains(p), cel[p].a != 0 else { continue }
            return (layer.id, SelectionMask.opaquePixels(of: cel))
        }
        return nil
    }

    /// The layers (and frames) a marquee works on: the timeline range, or
    /// every visible layer in the active frame. The background and locked
    /// layers are left out: they won't move, so they shouldn't widen the selection.
    private var marqueeScope: (layers: [Layer], frames: [UUID]) {
        if let r = timelineRange {
            return (storage.layers.filter { r.layers.contains($0.id) && $0.isVisible && !$0.isBackground && !$0.isLocked },
                    r.frames.compactMap { storage.frames.indices.contains($0) ? storage.frames[$0].id : nil })
        }
        return (storage.layers.filter { $0.isVisible && !$0.isBackground && !$0.isLocked },
                selectionAllFrames ? storage.frames.map(\.id) : [activeFrame.id])
    }

    /// The layers in scope with drawn pixels inside `shape`.
    private func layersWithContent(in shape: SelectionMask) -> [Layer] {
        let scope = marqueeScope
        return scope.layers.filter { layer in
            scope.frames.contains { frame in
                guard let cel = storage.cel(layer: layer.id, frame: frame) else { return false }
                return cel.pixels.indices.contains { cel.pixels[$0].a != 0 && shape.bits[$0] }
            }
        }
    }

    /// `shape` reduced to the drawn pixels of `layers` inside it. Nil when it
    /// holds nothing drawn, so selecting empty canvas still works.
    private func fittedToContent(_ shape: SelectionMask, layers: [Layer]) -> SelectionMask? {
        var content = emptyMask
        for layer in layers {
            for frame in marqueeScope.frames {
                guard let cel = storage.cel(layer: layer.id, frame: frame) else { continue }
                content = content.combined(with: SelectionMask.opaquePixels(of: cel), mode: .add)
            }
        }
        let fitted = shape.combined(with: content, mode: .intersect)
        return fitted.isEmpty ? nil : fitted
    }

    /// Replaces the selection as one undoable step.
    private func commitSelection(_ new: SelectionMask?) {
        applyTransformIfNeeded()
        let normalized = new?.isEmpty == true ? nil : new
        guard normalized != selection else { return }
        if selection != nil { lastSelection = selection }
        registerUndo(DocumentSnapshot(sprite: storage, selection: selection))
        selectionLayers = nil
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

    /// The cels a selection spans besides the timeline range: the layers a
    /// marquee caught (or the active one), in the active frame or in every
    /// frame. Nil when it's just the active cel.
    private var selectionScopeKeys: [CelKey]? {
        guard selection != nil else { return nil }
        let layers = storage.layers.filter { (selectionLayers ?? [activeLayerID]).contains($0.id) }.map(\.id)
        let frames = selectionAllFrames ? storage.frames.map(\.id) : [activeFrame.id]
        guard layers.count > 1 || frames.count > 1 else { return nil }
        return frames.flatMap { frame in layers.map { CelKey(layer: $0, frame: frame) } }
    }

    /// The cels an edit on the selection changes: every layer a marquee caught
    /// (in the active frame), every cel of the timeline range, or just the
    /// active cel. Hidden and locked layers are left out.
    private var selectionEditKeys: [CelKey] {
        let keys: [CelKey]
        if let range = timelineRange {
            keys = rangeKeys(range).flatMap { $0 }
        } else if let scope = selectionScopeKeys {
            keys = scope
        } else {
            return activeLayerEditable ? [activeCelKey] : []
        }
        let editable = Set(storage.layers.filter { $0.isVisible && !$0.isLocked }.map(\.id))
        let result = keys.filter { editable.contains($0.layer) }
        if result.isEmpty { notice = L10n.string("The layers are hidden or locked") }
        return result
    }

    /// Clears the selected pixels in every selected layer.
    func deleteSelection() {
        guard let mask = selection else { return }
        let keys = selectionEditKeys
        guard !keys.isEmpty else { return }
        let erase = keys.map { eraseColor(forLayer: $0.layer) }
        perform { s in
            for (key, color) in zip(keys, erase) {
                guard var cel = s.cels[key] else { continue }
                for i in cel.pixels.indices where mask.bits[i] { cel.pixels[i] = color }
                s.cels[key] = cel.isEmpty ? nil : cel
                s.syncLinks(from: key)
            }
        }
    }

    /// Fills the selection (or the whole cel) with the primary color. With
    /// several layers, each one recolors its own pixels and the empty part
    /// goes to the active layer, so the layers stay apart.
    func fillSelection() {
        let keys = selectionEditKeys
        guard !keys.isEmpty else { return }
        let mask = selection, color = primary, active = activeCelKey
        let (w, h) = (storage.width, storage.height)
        perform { s in
            // Pixels drawn in any of the layers: those stay with their own layer.
            var drawn = [Bool](repeating: false, count: w * h)
            if keys.count > 1 {
                for key in keys { if let cel = s.cels[key] { for i in cel.pixels.indices where cel.pixels[i].a != 0 { drawn[i] = true } } }
            }
            for key in keys {
                var cel = s.cels[key] ?? PixelImage(width: w, height: h)
                let isActive = keys.count == 1 || key == active
                for i in cel.pixels.indices where mask?.bits[i] ?? true {
                    let own = cel.pixels[i].a != 0
                    guard own || (isActive && !drawn[i]) else { continue }
                    cel.pixels[i] = color
                }
                s.cels[key] = cel.isEmpty ? nil : cel
                s.syncLinks(from: key)
            }
        }
    }

    /// Copies the selected pixels (or the whole cel) to the app clipboard and,
    /// as a PNG, to the system pasteboard. With several layers selected it
    /// copies them merged, as they look.
    func copy() {
        applyTransformIfNeeded()
        let keys = selectionEditKeys.filter { $0.frame == activeFrame.id }
        guard !keys.isEmpty else { return }
        let image: PixelImage
        if keys.count == 1 {
            guard let cel = storage.cels[keys[0]] else { return }
            image = cel
        } else {
            var merged = storage
            let layers = Set(keys.map(\.layer))
            for i in merged.layers.indices where !layers.contains(merged.layers[i].id) { merged.layers[i].isVisible = false }
            image = merged.composite(frameIndex: activeFrameIndex)
        }
        let mask = selection ?? SelectionMask(width: storage.width, height: storage.height, filled: true)
        guard let bounds = mask.bounds else { return }
        var cropped = image.cropped(to: bounds)
        let local = mask.cropped(to: bounds)
        for i in cropped.pixels.indices where !local.bits[i] { cropped.pixels[i] = .clear }
        PixelClipboard.store(cropped, origin: PixelPoint(x: bounds.minX, y: bounds.minY))
    }

    func cut() {
        copy()
        if selection != nil { deleteSelection() } else { clearActiveCel() }
    }

    private func clearActiveCel() {
        guard activeLayerEditable else { return }
        let key = activeCelKey, erase = eraseColor, (w, h) = (storage.width, storage.height)
        perform { $0.cels[key] = erase == .clear ? nil : PixelImage(width: w, height: h, fill: erase) }
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
        beginFloating(image, at: fits ? origin : PixelPoint(x: (w - image.width) / 2, y: (h - image.height) / 2))
    }

    /// Puts `image` on the active cel as floating pixels, ready to move,
    /// scale or rotate; tapping outside applies it.
    private func beginFloating(_ image: PixelImage, at origin: PixelPoint) {
        let (w, h) = (storage.width, storage.height)
        let key = activeCelKey
        transformStart = DocumentSnapshot(sprite: storage, selection: selection)
        floatingBase = storage.cels[key] ?? PixelImage(width: w, height: h)
        var f = FloatingSelection(celKey: key, source: image, sourceMask: SelectionMask.opaquePixels(of: image), at: origin)
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

    // MARK: Text

    /// Writes `text` at the tapped point with the primary color (outline in
    /// the secondary), as floating pixels like a paste. Returns false when
    /// nothing visible would be written.
    @discardableResult
    func placeText(_ text: String) -> Bool {
        let anchor = textAnchor
        textAnchor = nil
        guard let anchor, activeLayerEditable else { return false }
        var outlineColor = secondary
        outlineColor.a = 255
        guard let image = TextRenderer.render(text, style: textStyle, color: primary, outlineColor: outlineColor) else { return false }
        applyTransformIfNeeded()
        cancelStroke()
        stopPlayback()
        let at = PixelPoint(x: anchor.x - (textStyle.outline ? 1 : 0), y: anchor.y - (textStyle.outline ? 1 : 0))
        beginFloating(image, at: at)
        toolAfterTransform = .text
        return true
    }

    private func restoreToolAfterTransform() {
        guard let next = toolAfterTransform else { return }
        toolAfterTransform = nil
        tool = next
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
        let targets = rangeTransformTargets()
        var mask: SelectionMask
        if let selection {
            mask = selection
        } else if wholeCanvas {
            mask = SelectionMask(width: w, height: h, filled: true)
        } else {
            mask = SelectionMask.opaquePixels(of: cel)
            // Several cels move as one block: a rectangle around all their pixels.
            if !targets.isEmpty {
                let union = ([mask.bounds] + targets.map { t in storage.cels[t.key].flatMap { SelectionMask.opaquePixels(of: $0).bounds } })
                    .compactMap { $0 }
                    .reduce(nil as PixelRect?) { $0?.union($1) ?? $1 }
                if let union { mask = SelectionMask.rect(union, width: w, height: h) }
            }
        }
        guard let bounds = mask.bounds else { return }
        var source = cel.cropped(to: bounds)
        let localMask = mask.cropped(to: bounds)
        for i in source.pixels.indices where !localMask.bits[i] { source.pixels[i] = .clear }
        var base = cel
        let erase = eraseColor
        if !copy { for i in base.pixels.indices where mask.bits[i] { base.pixels[i] = erase } }

        transformStart = DocumentSnapshot(sprite: storage, selection: selection)
        floatingBase = base
        var f = FloatingSelection(celKey: key, source: source, sourceMask: localMask, at: PixelPoint(x: bounds.minX, y: bounds.minY))
        f.algorithm = rotationAlgorithm
        floating = f
        rangeFloating = targets.compactMap { target in
            guard let image = storage.cels[target.key] else { return nil }
            var source = image.cropped(to: bounds)
            for i in source.pixels.indices where !localMask.bits[i] { source.pixels[i] = .clear }
            var base = image
            if !copy {
                let erase = eraseColor(forLayer: target.key.layer)
                for i in base.pixels.indices where mask.bits[i] { base.pixels[i] = erase }
            }
            var other = FloatingSelection(celKey: target.key, source: source, sourceMask: localMask, at: PixelPoint(x: bounds.minX, y: bounds.minY))
            other.algorithm = rotationAlgorithm
            return RangeFloating(base: base, floating: other, linked: target.linked)
        }
        transformExtraCels = rangeFloating.count
        floatingDirty = bounds
        isTransforming = true
        renderFloating()
    }

    // MARK: Transforming a timeline range

    struct RangeFloating {
        var base: PixelImage
        var floating: FloatingSelection
        /// Cels linked to this one, which get the same result.
        var linked: [CelKey]
    }

    /// The cels of the timeline range besides the active one: one per link
    /// group, skipping locked layers and empty cels.
    private func rangeTransformTargets() -> [(key: CelKey, linked: [CelKey])] {
        let keys: [CelKey]
        if let range = timelineRange {
            keys = rangeKeys(range).flatMap { $0 }
        } else if let scope = selectionScopeKeys {
            keys = scope
        } else {
            return []
        }
        let active = activeCelKey, activeGroup = storage.links[active]
        let locked = Set(storage.layers.filter(\.isLocked).map(\.id))
        var result: [(key: CelKey, linked: [CelKey])] = []
        var byGroup: [UUID: Int] = [:]
        for key in keys where key != active && storage.cels[key] != nil && !locked.contains(key.layer) {
            let group = storage.links[key]
            if let group, group == activeGroup { continue }
            if let group, let index = byGroup[group] {
                result[index].linked.append(key)
                continue
            }
            if let group { byGroup[group] = result.count }
            result.append((key, []))
        }
        return result
    }

    private func eraseColor(forLayer id: UUID) -> PixelColor {
        guard storage.layers.first(where: { $0.id == id })?.isBackground == true else { return .clear }
        var color = secondary
        color.a = 255
        return color
    }

    /// Lines the other cels' boxes up with the active one before a flip or a
    /// 90° turn, which depend on the box's current flip state.
    private func syncRangeBoxes() {
        guard let box = floating?.box else { return }
        for i in rangeFloating.indices { rangeFloating[i].floating.box = box }
    }

    /// Floating pixels drawn over the cel they were lifted from.
    private static func stamp(_ rendered: (image: PixelImage, origin: PixelPoint, mask: SelectionMask), onto base: PixelImage) -> PixelImage {
        var cel = base
        let o = rendered.origin
        for y in 0..<rendered.image.height {
            for x in 0..<rendered.image.width {
                let p = rendered.image[x, y]
                guard p.a != 0, rendered.mask[o.x + x, o.y + y] else { continue }
                cel[o.x + x, o.y + y] = p.blended(over: cel[o.x + x, o.y + y])
            }
        }
        return cel
    }

    /// Drops the transform into the other cels of the range.
    private func applyRangeFloating() {
        guard let box = floating?.box else { return }
        for var item in rangeFloating {
            item.floating.box = box
            let cel = Self.stamp(item.floating.render(spriteWidth: storage.width, spriteHeight: storage.height), onto: item.base)
            let result: PixelImage? = cel.isEmpty ? nil : cel
            for key in [item.floating.celKey] + item.linked { storage.cels[key] = result }
        }
        rangeFloating = []
        transformExtraCels = 0
    }

    /// Draws the floating pixels over the cel they were lifted from.
    private func renderFloating() {
        guard var f = floating, let base = floatingBase else { return }
        let rendered = f.render(spriteWidth: storage.width, spriteHeight: storage.height)
        floating = f
        storage.cels[f.celKey] = Self.stamp(rendered, onto: base)
        // The other layers of a multi-layer selection follow live in this frame;
        // other frames of a timeline range change when the transform is applied.
        for i in rangeFloating.indices where rangeFloating[i].floating.celKey.frame == f.celKey.frame {
            rangeFloating[i].floating.box = f.box
            let other = rangeFloating[i].floating.render(spriteWidth: storage.width, spriteHeight: storage.height)
            let cel = Self.stamp(other, onto: rangeFloating[i].base)
            for key in [rangeFloating[i].floating.celKey] + rangeFloating[i].linked { storage.cels[key] = cel }
        }
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

    /// Drops the floating pixels into the cel and deselects, as one undo step.
    func applyTransform() {
        guard isTransforming, let start = transformStart, let key = floating?.celKey else { return }
        applyRangeFloating()
        floating = nil
        floatingBase = nil
        transformStart = nil
        floatingDirty = nil
        transformDrag = nil
        isTransforming = false
        if storage.cels[key]?.isEmpty == true { storage.cels[key] = nil }
        // Applying finishes the job: the selection goes away (Reselect brings it back).
        if let selection { lastSelection = selection }
        selection = nil
        selectionLayers = nil
        if start != DocumentSnapshot(sprite: storage, selection: selection) { registerUndo(start) }
        restoreToolAfterTransform()
        changed()
    }

    func cancelTransform() {
        guard isTransforming, let start = transformStart else { return }
        rangeFloating = []
        transformExtraCels = 0
        floating = nil
        floatingBase = nil
        transformStart = nil
        floatingDirty = nil
        transformDrag = nil
        isTransforming = false
        storage = start.sprite
        selection = start.selection
        restoreToolAfterTransform()
        changed()
    }

    func applyTransformIfNeeded() {
        finishPendingShape()
        if isTransforming { applyTransform() }
    }

    /// With a selection tool in replace mode, a drag that starts inside the
    /// selection moves its pixels instead of selecting again (as in Aseprite).
    func dragMovesSelection(at p: PixelPoint) -> Bool {
        guard tool.isSelection, tool != .magicWand, selectionMode == .replace, !isTransforming else { return false }
        return selection?.contains(p) ?? false
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
        syncRangeBoxes()
        floating?.flip(horizontal: horizontal)
        for i in rangeFloating.indices { rangeFloating[i].floating.flip(horizontal: horizontal) }
        renderFloating()
    }

    /// Rotates the selection 90°, or the whole cel when nothing is selected.
    func rotate90(clockwise: Bool) {
        if !isTransforming { beginTransform(wholeCanvas: true) }
        syncRangeBoxes()
        floating?.rotate90(clockwise: clockwise)
        for i in rangeFloating.indices { rangeFloating[i].floating.rotate90(clockwise: clockwise) }
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
/// Like Aseprite, it remembers whether whole frames or whole layers were picked.
struct TimelineRange: Equatable {
    enum Kind { case cels, frames, layers }
    var kind = Kind.cels
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
            kind: .cels,
            layers: Set(ids[min(a, b)...max(a, b)]),
            frames: min(anchor.frame, frameIndex)...max(anchor.frame, frameIndex)
        )
    }

    /// Tap on a frame number while selecting: whole columns, every layer.
    func extendRange(frameIndex: Int) {
        let all = Set(sprite.layers.map(\.id))
        let start = timelineRange.map { _ in rangeAnchor?.frame ?? frameIndex } ?? frameIndex
        if timelineRange == nil { rangeAnchor = (sprite.layers.last!.id, frameIndex) }
        timelineRange = TimelineRange(kind: .frames, layers: all, frames: min(start, frameIndex)...max(start, frameIndex))
    }

    /// Tap on a layer name while selecting: whole rows, every frame.
    func extendRange(layerRow layer: UUID) {
        let ids = sprite.layers.map(\.id)
        if timelineRange == nil || rangeAnchor == nil { rangeAnchor = (layer, activeFrameIndex) }
        guard let a = ids.firstIndex(of: rangeAnchor!.layer), let b = ids.firstIndex(of: layer) else { return }
        timelineRange = TimelineRange(kind: .layers, layers: Set(ids[min(a, b)...max(a, b)]), frames: 0...(sprite.frames.count - 1))
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
        var placed = range.frames
        perform { placed = $0.moveFrames(range.frames, to: range.frames.upperBound + 1, copy: true) }
        selectFrames(placed)
    }

    private func selectFrames(_ frames: ClosedRange<Int>) {
        timelineRange = TimelineRange(kind: .frames, layers: Set(sprite.layers.map(\.id)), frames: frames)
        rangeAnchor = (sprite.layers.last!.id, frames.lowerBound)
        activeFrameIndex = frames.lowerBound
    }

    /// Reverses the order of the selected frames (Aseprite's Frame > Reverse Frames).
    func reverseRangeFrames() {
        guard let range = timelineRange, range.frames.count > 1 else { return }
        perform { s in
            let reversed = Array(s.frames[range.frames].reversed())
            s.frames.replaceSubrange(range.frames, with: reversed)
        }
    }

    // MARK: Drag and drop

    private func layerIndices(_ range: TimelineRange) -> [Int] {
        sprite.layers.indices.filter { range.layers.contains(sprite.layers[$0].id) }
    }

    /// Drops the selected block after dragging it from the cel (`fromLayer`,
    /// `fromFrame`) to (`toLayer`, `toFrame`). Cel blocks keep their offset
    /// from the grabbed cel, frame blocks are inserted at the target frame and
    /// layer blocks at the target layer. `dragCopies` copies instead of moving.
    func dropRange(from: (layer: UUID, frame: Int), to: (layer: UUID, frame: Int)) {
        guard let range = timelineRange else { return }
        let ids = sprite.layers.map(\.id)
        guard let fromLayer = ids.firstIndex(of: from.layer), let toLayer = ids.firstIndex(of: to.layer) else { return }
        let copy = dragCopies
        switch range.kind {
        case .cels:
            let indices = layerIndices(range)
            var applied = (dLayers: 0, dFrames: 0)
            perform { applied = $0.moveCels(layerIndices: indices, frameRange: range.frames, dLayers: toLayer - fromLayer, dFrames: to.frame - from.frame, copy: copy) }
            guard applied != (0, 0) else { return }
            let layers = Set(indices.map { sprite.layers[$0 + applied.dLayers].id })
            let frames = (range.frames.lowerBound + applied.dFrames)...(range.frames.upperBound + applied.dFrames)
            timelineRange = TimelineRange(kind: .cels, layers: layers, frames: frames)
            rangeAnchor = (sprite.layers[(indices.last ?? 0) + applied.dLayers].id, frames.lowerBound)
            selectCel(layer: sprite.layers[min(sprite.layers.count - 1, toLayer)].id, frameIndex: to.frame)
        case .frames:
            guard copy || !range.frames.contains(to.frame) else { return }
            let destination = to.frame > range.frames.upperBound ? to.frame + 1 : to.frame
            var placed = range.frames
            perform { placed = $0.moveFrames(range.frames, to: destination, copy: copy) }
            selectFrames(placed)
        case .layers:
            var placed: [UUID] = []
            perform { placed = $0.moveLayers(range.layers, to: toLayer, copy: copy) }
            guard !placed.isEmpty else { return }
            timelineRange = TimelineRange(kind: .layers, layers: Set(placed), frames: 0...(sprite.frames.count - 1))
            rangeAnchor = (placed.last!, activeFrameIndex)
            activeLayerID = placed.last!
        }
    }

    // MARK: Copy and paste

    /// Copies the selected cels, frames or layers to the timeline clipboard.
    func copyRange() {
        guard let range = timelineRange else { return }
        let s = sprite
        let frameIDs = range.frames.compactMap { s.frames.indices.contains($0) ? s.frames[$0].id : nil }
        switch range.kind {
        case .cels:
            let rows = layerIndices(range).reversed().map { li in
                frameIDs.map { s.content(CelKey(layer: s.layers[li].id, frame: $0)) }
            }
            TimelineClipboard.shared.content = .cels(rows)
        case .frames:
            TimelineClipboard.shared.content = .frames(range.frames.filter { s.frames.indices.contains($0) }.map { f in
                (s.frames[f].duration, s.layers.map { s.content(CelKey(layer: $0.id, frame: s.frames[f].id)) })
            })
        case .layers:
            TimelineClipboard.shared.content = .layers(layerIndices(range).map { li in
                (s.layers[li], s.frames.map { s.content(CelKey(layer: s.layers[li].id, frame: $0.id)) })
            })
        }
        notice = L10n.string("Copied to the timeline")
    }

    /// Pastes copied cels with their top-left cel on the active cel. Rows past
    /// the bottom layer are dropped; frames are added past the end.
    func pasteCels() {
        guard case .cels(let rows) = TimelineClipboard.shared.content,
              let top = sprite.layers.firstIndex(where: { $0.id == activeLayerID }) else { return }
        let start = activeFrameIndex, w = sprite.width, h = sprite.height
        perform { s in
            s.ensureFrames(start + (rows.first?.count ?? 0))
            for (r, row) in rows.enumerated() where top - r >= 0 {
                for (c, cel) in row.enumerated() {
                    let key = CelKey(layer: s.layers[top - r].id, frame: s.frames[start + c].id)
                    s.setContent(cel.fitted(width: w, height: h), key)
                    s.links[key] = nil
                }
            }
            s.normalizeLinks()
        }
    }

    /// Inserts copied frames after the active one; cels go to layers by position.
    func pasteFrames() {
        guard case .frames(let copied) = TimelineClipboard.shared.content else { return }
        let at = activeFrameIndex + 1, w = sprite.width, h = sprite.height
        perform { s in
            for (offset, item) in copied.enumerated() {
                let frame = Frame(duration: item.duration)
                s.insertFrame(frame, at: at + offset)
                for (li, cel) in item.cels.enumerated() where s.layers.indices.contains(li) {
                    s.setContent(cel.fitted(width: w, height: h), CelKey(layer: s.layers[li].id, frame: frame.id))
                }
            }
        }
        selectFrames(at...(at + copied.count - 1))
    }

    /// Inserts copied layers above the active one; frames are added if needed.
    func pasteLayers() {
        guard case .layers(let copied) = TimelineClipboard.shared.content,
              let index = sprite.layers.firstIndex(where: { $0.id == activeLayerID }) else { return }
        let w = sprite.width, h = sprite.height
        var newIDs: [UUID] = []
        perform { s in
            s.ensureFrames(copied.map(\.cels.count).max() ?? 0)
            for (offset, item) in copied.enumerated() {
                var layer = item.layer
                layer.id = UUID()
                layer.isBackground = false
                newIDs.append(layer.id)
                s.layers.insert(layer, at: index + 1 + offset)
                for (f, cel) in item.cels.enumerated() {
                    s.setContent(cel.fitted(width: w, height: h), CelKey(layer: layer.id, frame: s.frames[f].id))
                }
            }
        }
        if let last = newIDs.last { activeLayerID = last }
    }

    // MARK: Frames, tags and cels

    /// Sets the duration of every selected frame (Aseprite's Frame Properties on a range).
    func setRangeDuration(_ ms: Int) {
        guard let range = timelineRange else { return }
        perform { s in
            for f in range.frames where s.frames.indices.contains(f) { s.frames[f].duration = min(Self.maxFrameDuration, max(10, ms)) }
        }
    }

    /// The frames a new tag or the loop section covers: the selection, or the active frame.
    private var tagFrames: ClosedRange<Int> {
        timelineRange?.frames ?? activeFrameIndex...activeFrameIndex
    }

    /// Creates a tag over the selected frames (or the active one) and returns it.
    @discardableResult
    func addTag() -> FrameTag {
        let frames = tagFrames
        let tag = FrameTag(
            name: L10n.string("Tag %d", sprite.tags.count + 1),
            from: frames.lowerBound,
            to: min(frames.upperBound, sprite.frames.count - 1),
            color: FrameTag.colors[sprite.tags.count % FrameTag.colors.count]
        )
        perform { $0.tags.append(tag) }
        return tag
    }

    /// Aseprite's Set Loop Section: a tag named "Loop" over the selected
    /// frames, reused if it already exists. https://www.aseprite.org/docs/loop/
    @discardableResult
    func setLoopSection() -> FrameTag {
        let frames = tagFrames
        let last = sprite.frames.count - 1
        if var loop = sprite.tags.first(where: { $0.name == Self.loopTagName }) {
            loop.from = frames.lowerBound
            loop.to = min(frames.upperBound, last)
            updateTag(loop)
            return loop
        }
        let tag = FrameTag(name: Self.loopTagName, from: frames.lowerBound, to: min(frames.upperBound, last), color: FrameTag.colors[7])
        perform { $0.tags.append(tag) }
        return tag
    }

    static let loopTagName = "Loop"

    /// Opacity of one cel; linked cels share it.
    func setCelOpacity(_ opacity: Double, layer: UUID, frameIndex: Int) {
        guard sprite.frames.indices.contains(frameIndex) else { return }
        let key = CelKey(layer: layer, frame: sprite.frames[frameIndex].id)
        guard sprite.cels[key] != nil else { return }
        let value = min(1, max(0, opacity))
        perform { s in
            let group = s.links[key]
            for k in s.cels.keys where k == key || (group != nil && s.links[k] == group) {
                s.celOpacity[k] = value < 1 ? value : nil
            }
        }
    }

    func celOpacity(layer: UUID, frameIndex: Int) -> Double {
        guard sprite.frames.indices.contains(frameIndex) else { return 1 }
        return sprite.celOpacity[CelKey(layer: layer, frame: sprite.frames[frameIndex].id)] ?? 1
    }

    /// Copies the selected layers above them.
    func duplicateRangeLayers() {
        guard let range = timelineRange, let top = layerIndices(range).last else { return }
        var placed: [UUID] = []
        perform { placed = $0.moveLayers(range.layers, to: top, copy: true) }
        guard let last = placed.last else { return }
        timelineRange = TimelineRange(kind: .layers, layers: Set(placed), frames: 0...(sprite.frames.count - 1))
        rangeAnchor = (last, activeFrameIndex)
        activeLayerID = last
    }

    /// Deletes the selected layers (at least one layer stays).
    func deleteRangeLayers() {
        guard let range = timelineRange, range.layers.count < sprite.layers.count else {
            notice = L10n.string("A sprite needs at least one layer")
            return
        }
        perform { s in
            s.layers.removeAll { range.layers.contains($0.id) }
            s.cels = s.cels.filter { !range.layers.contains($0.key.layer) }
            s.normalizeLinks()
        }
        endRangeSelection()
    }

    /// Copies a layer with its cels above itself (Layer > Duplicate).
    func duplicateLayer(_ id: UUID) {
        guard let index = sprite.layers.firstIndex(where: { $0.id == id }) else { return }
        var placed: [UUID] = []
        perform { placed = $0.moveLayers([id], to: index, copy: true) }
        if let copy = placed.first { activeLayerID = copy }
    }
}

/// Paints single pixels with an ink, each at most once per stroke at its
/// strongest alpha, always starting from the cel as the stroke found it.
private struct Painter {
    let ink: Ink
    let color: PixelColor
    let original: PixelImage?
    let mask: SelectionMask?
    let ramp: [PixelColor]
    let direction: ShadeDirection
    var coverage: [UInt8]

    mutating func paint(_ q: PixelPoint, alpha: UInt8, on image: inout PixelImage) {
        guard image.contains(q), mask?.contains(q) ?? true else { return }
        let i = q.y * image.width + q.x
        guard alpha > coverage[i] else { return }
        coverage[i] = alpha
        let ramp = ramp, direction = direction
        image.pixels[i] = ink.apply(color, over: original?.pixels[i] ?? .clear, alpha: alpha) { direction.step($0, in: ramp) }
    }
}
