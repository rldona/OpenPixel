import CoreGraphics
import Foundation
import ImageIO
import UIKit
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
/// Which sides of the canvas a canvas-size drag moves.
struct CanvasEdges: OptionSet, Sendable {
    let rawValue: Int
    static let left = CanvasEdges(rawValue: 1), right = CanvasEdges(rawValue: 2)
    static let top = CanvasEdges(rawValue: 4), bottom = CanvasEdges(rawValue: 8)
}

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

extension SpriteDocument {
    /// How far `index` is from the active frame when the onion skin shows it
    /// (negative before, positive after), or nil when it doesn't.
    func onionOffset(of index: Int) -> Int? {
        guard onionSkin, !isPlaying else { return nil }
        let offset = index - activeFrameIndex
        let settings = onionSettings
        guard offset != 0, offset >= -settings.previous, offset <= settings.next, structure.frames.indices.contains(index) else { return nil }
        if settings.onlyInTag, let tag = structure.tag(containing: activeFrameIndex), !tag.contains(index) { return nil }
        return offset
    }
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
    private(set) var revision = 0 {
        didSet {
            let key = StructureKey(storage)
            if key != structureKey {
                structureKey = key
                structureRevision &+= 1
            }
        }
    }
    /// Bumped only when something besides the pixels changes: layers,
    /// frames, tags, palette, links, which cels have content, grid, slices.
    /// Most of the interface (timeline, side panel, options bar) reads
    /// `structure`, so a stroke that only changes pixels doesn't rebuild it.
    private(set) var structureRevision = 0
    @ObservationIgnored private var structureKey: StructureKey?
    /// The sprite, for views that don't show its pixels.
    var structure: Sprite {
        _ = structureRevision
        return storage
    }
    /// Called with the changed area while a stroke is in progress, so the
    /// canvas can redraw just that area without a SwiftUI update.
    @ObservationIgnored var onCanvasChange: ((PixelRect) -> Void)?
    /// The canvas view that receives `onCanvasChange` and `onOverlayChange`.
    @ObservationIgnored weak var canvasOwner: AnyObject?
    private(set) var hasUnsavedChanges = false

    /// Changing the active cel drops any floating pixels first, like Aseprite.
    var activeLayerID: UUID {
        willSet { if newValue != activeLayerID { finishPendingShape() } }
        didSet {
            guard oldValue != activeLayerID else { return }
            applyTransformIfNeeded()
            notifyScripts(.site)
        }
    }
    var activeFrameIndex = 0 {
        willSet { if newValue != activeFrameIndex { finishPendingShape() } }
        didSet {
            guard oldValue != activeFrameIndex else { return }
            applyTransformIfNeeded()
            notifyScripts(.site)
        }
    }
    private(set) var tool: Tool = .pencil
    private var previousTool: Tool = .pencil
    /// The frame playback started from, for Preferences > Rewind on stop.
    @ObservationIgnored private var playbackStartFrame: Int?
    var primary: PixelColor { didSet { if oldValue != primary { notifyScripts(.foregroundColor) } } }
    var secondary: PixelColor { didSet { if oldValue != secondary { notifyScripts(.backgroundColor) } } }
    var symmetry = Symmetry()
    var tiledMode = TiledMode.none
    var brushSize = 1
    var brushShape = BrushShape.square
    /// Angle of the line brush, in degrees.
    var brushAngle = 45
    /// A brush made from part of the drawing (Edit > New brush), painted with its own colors.
    private(set) var customBrush: PixelImage?
    var useCustomBrush = false
    /// The custom brush paints the primary color, keeping only its shape.
    var customBrushUsesColor = false
    /// Spray: radius of the area the dots land in, and dots per Pencil sample.
    var sprayWidth = 8
    var spraySpeed = 4
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
    /// How different (0...255 per channel) a color can be and still be filled.
    var fillTolerance = 0
    /// Contiguous fills also spread through corners (8-connected).
    var fillDiagonal = false
    /// The bucket looks at every visible layer to find the area, but paints the active one.
    var fillSampleAllLayers = false
    var gradientShape = GradientShape.linear
    var gradientDither = GradientDither.none
    /// The eyedropper reads only the active layer instead of the whole image.
    var eyedropperActiveLayer = false
    var showGrid = true
    /// The sprite's grid (`Sprite.grid`) drawn over the canvas.
    var showTileGrid = false
    /// Marquees and moves snap to the grid.
    var snapToGrid = false
    /// The paint bucket doesn't cross grid lines.
    var fillStopsAtGrid = false
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
    /// Edit > Canvas > Canvas size: the proposed canvas, in the current canvas's
    /// coordinates, while its edges are being dragged on the canvas.
    var canvasResize: PixelRect?
    /// Its sides snap to grid lines.
    var canvasResizeInCells = UserDefaults.standard.bool(forKey: "canvasResizeInCells") {
        didSet { UserDefaults.standard.set(canvasResizeInCells, forKey: "canvasResizeInCells") }
    }
    /// Open script dialogs, shown as floating windows over the editor.
    var scriptDialogs: [ScriptDialog] = []
    /// A script's error or `app.alert`, shown as an alert.
    var scriptMessage: ScriptMessage?
    /// Scripts still running: waiting on a dialog, or with dialogs open, listeners or timers.
    @ObservationIgnored private(set) var scriptEngines: [ScriptEngine] = []
    /// A script's own changes don't become events for scripts.
    @ObservationIgnored private var applyingScript = false
    @ObservationIgnored private var siteEventPending = false
    /// The Color Shading window is open (the side panel's Color shading button).
    /// It and Hue/Saturation take turns: opening one closes the other.
    var isShowingColorShading = false
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
    /// The rail's selection opacity slider (see `selectionOpacity`).
    @ObservationIgnored var selectionFade: SelectionFade?
    @ObservationIgnored var selectionFadeStart: DocumentSnapshot?

    /// Called when the selection outline or the transform box changes.
    @ObservationIgnored var onOverlayChange: (() -> Void)?

    // Transform
    @ObservationIgnored private var floating: FloatingSelection?
    /// A reference image being dragged with the Move tool.
    @ObservationIgnored private var referenceDrag: (layer: UUID, start: CGPoint, frame: CGRect, before: Sprite)?
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
    /// Moving the pixels stretches them instead of tearing them away: the gap
    /// fills with their trailing edge (Aseprite's Ctrl+drag). Lasts one transform.
    var stretchMove = false {
        didSet { if stretchMove != oldValue, floating != nil { renderFloating() } }
    }
    /// Snaps free rotation to 15° steps.
    var snapAngle = true
    /// The floating pixels' box, for the canvas handles.
    var transformBox: TransformBox? { floating?.box }

    // The stacks aren't observed: every stroke pushes onto them, and only
    // whether they're empty matters to the interface.
    @ObservationIgnored private var undoStack: [DocumentSnapshot] = [] { didSet { if canUndo == undoStack.isEmpty { canUndo = !undoStack.isEmpty } } }
    @ObservationIgnored private var redoStack: [DocumentSnapshot] = [] { didSet { if canRedo == redoStack.isEmpty { canRedo = !redoStack.isEmpty } } }
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
    /// What drawing pixels on a tilemap does to its tiles.
    var tilesetMode = TilesetMode.auto
    /// On a tilemap, paint pixels or place whole tiles.
    var tileDrawMode = TileDrawMode.pixels
    /// The tile placed in tiles mode.
    var selectedTile = 1
    /// The stroke in progress places tiles instead of pixels.
    @ObservationIgnored private var tileStroke = false
    /// The slice the slice tool works on.
    var activeSliceID: UUID? { didSet { onOverlayChange?() } }
    /// A slice being drawn, moved or resized: which edges follow the drag
    /// (all four when moving), and the sprite before the drag for undo.
    @ObservationIgnored private var sliceDrag: (slice: UUID, start: PixelPoint, bounds: PixelRect, edges: SliceEdges, before: Sprite)?
    /// The area a gradient drag fills, found like the paint bucket's at the touch-down point.
    @ObservationIgnored private var gradientRegion: SelectionMask?
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
    static let maxBrushSize = 32
    @ObservationIgnored private var playTask: Task<Void, Never>?

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
        self.structureKey = StructureKey(sprite)
    }

    var file: SpriteFile { SpriteFile(name: name, sprite: sprite) }
    private(set) var canUndo = false
    private(set) var canRedo = false
    var activeLayer: Layer? { structure.layers.first { $0.id == activeLayerID } }
    var activeFrame: Frame { structure.frames[activeFrameIndex] }

    func markSaved() { hasUnsavedChanges = false }

    // MARK: - History

    /// Commits a change. Edits always land in the active cel, so its linked
    /// cels are brought up to date here.
    /// Where a change came from, for scripts' change events.
    private enum ChangeOrigin { case stroke, command, undo }

    private func changed(_ origin: ChangeOrigin = .command) {
        notifyScripts(.change(fromUndo: origin == .undo, command: origin == .command))
        if storage.frames.indices.contains(activeFrameIndex) { storage.syncLinks(from: activeCelKey) }
        // Tilemaps follow whatever was drawn on them.
        if storage.layers.contains(where: \.isTilemap) || !storage.tilemaps.isEmpty { storage.syncTilemaps(mode: tilesetMode) }
        revision &+= 1
        if !hasUnsavedChanges { hasUnsavedChanges = true }
    }

    private func registerUndo(_ snapshot: DocumentSnapshot) {
        undoStack.append(snapshot)
        // Preferences > Undo limit.
        if undoStack.count > EditorSettings.undoLimit { undoStack.removeFirst(undoStack.count - EditorSettings.undoLimit) }
        redoStack.removeAll()
    }

    /// Applies a structural change as one undoable step.
    private func perform(_ change: (inout Sprite) -> Void) {
        applyTransformIfNeeded()
        stopPlayback()
        let before = storage
        change(&storage)
        // Whatever moved, groups stay right above their children.
        if storage.layers.contains(where: { $0.isGroup || $0.parent != nil }) { storage.normalizeGroups() }
        storage.normalizeSlices()
        guard storage != before else { return }
        registerUndo(DocumentSnapshot(sprite: before, selection: selection))
        fixSelection()
        changed()
    }

    /// While transforming, undo cancels the transform.
    func undo() {
        if isAdjustingHueSaturation { return endHueSaturation(apply: nil, everyCel: false) }
        if isOutlining { return endOutline(apply: nil, everyCel: false) }
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
        changed(.undo)
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
        // Slices show more strongly with the slice tool.
        onOverlayChange?()
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
    func toggleEraser() { toggle(.eraser) }

    /// Switches to `other`, or back to the previous tool when it's already in use.
    func toggle(_ other: Tool) {
        if tool == other {
            select(previousTool == other ? .pencil : previousTool)
        } else {
            select(other)
        }
    }

    /// An Apple Pencil double tap or squeeze.
    func perform(_ action: PencilAction) {
        switch action {
        case .system, .eraser: toggle(.eraser)
        case .swapColors: swapColors()
        case .eyedropper: toggle(.eyedropper)
        case .undo: undo()
        case .nothing: break
        }
    }

    func swapColors() {
        (primary, secondary) = (secondary, primary)
    }

    func pickColor(at p: PixelPoint) {
        let image = eyedropperActiveLayer
            ? sprite.cels[activeCelKey] ?? PixelImage(width: sprite.width, height: sprite.height)
            : sprite.composite(frameIndex: activeFrameIndex)
        guard image.contains(p), !image[p].isTransparent else { return }
        primary = image[p]
    }

    // MARK: - Strokes
    //
    // While a stroke is in progress pixels change in `storage` without bumping
    // `revision`; the canvas is told which area changed through `onCanvasChange`.
    // The stroke is committed (one undo step, one SwiftUI update) when it ends.

    var activeCelKey: CelKey { CelKey(layer: activeLayerID, frame: activeFrame.id) }

    /// `pressure` is the Apple Pencil's force, 0...1 (1 for fingers).
    func beginStroke(at point: PixelPoint, pressure: Double = 1) {
        let point = snapped(point)
        // In tiled mode a stroke can start on a copy around the sprite; tools
        // that act on one spot need it inside, freehand strokes wrap as they paint.
        let p = tool.usesBrush || tool == .spray ? point : tiledMode.wrap(point, width: storage.width, height: storage.height)
        if isBuildingShape {
            if tool.buildsOverTouches { return continuePendingShape(at: p) }
            finishPendingShape()
        }
        cancelStroke()
        stopPlayback()
        if tool == .slice { return beginSliceDrag(at: p) }
        if tool == .eyedropper {
            if activeLayer?.isTilemap == true, tileDrawMode == .tiles { return pickTile(at: p) }
            pickColor(at: p)
            return
        }
        if tool.isSelection {
            beginSelection(at: p)
            return
        }
        applyTransformIfNeeded()
        guard let layer = activeLayer else { return }
        if layer.isGroup { notice = L10n.string("“%@” is a group: pick a layer inside it to draw", layer.name); return }
        if !storage.shows(layer) { notice = L10n.string("Layer “%@” is hidden", layer.name); return }
        if storage.locks(layer) { notice = L10n.string("Layer “%@” is locked", layer.name); return }
        if layer.isReference { notice = L10n.string("“%@” is a reference layer: use the Move tool to place it", layer.name); return }
        if tool == .text {
            textAnchor = p
            return
        }

        if layer.isTilemap, tileDrawMode == .tiles, [.pencil, .eraser, .bucket].contains(tool) {
            strokeStart = storage
            tileStroke = true
            if tool == .bucket {
                fillTiles(at: p)
                return endStroke()
            }
            return placeTile(at: p)
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
        case .gradient:
            shapeOrigin = p
            gradientRegion = bucketRegion(at: p)
            drawShape(to: p)
        case .curve, .polygon:
            pendingShape = tool == .curve ? [p, p, p, p] : [p]
            pendingBeforeDrag = []
            pendingDragging = true
            pendingShapeStage = 1
            redrawPendingShape()
        case .spray:
            lastPoint = p
            spray(at: [p])
        default:
            lastPoint = p
            strokePath = []
            contourPath = [p]
            plotFreehand([p], pressures: [pressure])
        }
    }

    /// Aseprite's Snap to Grid for drawing tools: the point goes to the closest
    /// grid corner, offset so the brush's top-left pixel lands on it (a brush
    /// as big as a cell fills whole cells). Selections, moves and slices snap
    /// in their own way; the bucket has Stop at grid.
    private func snapped(_ p: PixelPoint) -> PixelPoint {
        guard snapToGrid, !(activeLayer?.isTilemap == true && tileDrawMode == .tiles) else { return p }
        let tools: Set<Tool> = [.pencil, .eraser, .spray, .line, .curve, .polygon, .contour, .rectangle, .ellipse, .gradient, .text]
        guard tools.contains(tool) else { return p }
        var cx = 0, cy = 0
        if let brush = activeCustomBrush {
            cx = (brush.width - 1) / 2
            cy = (brush.height - 1) / 2
        } else if tool.usesBrush {
            cx = (effectiveBrushSize - 1) / 2
            cy = cx
        }
        let v = storage.grid.closestVertex(to: PixelPoint(x: p.x - cx, y: p.y - cy))
        return PixelPoint(x: v.x + cx, y: v.y + cy)
    }

    /// With snapping, a rectangle or ellipse drawn from corner to corner covers
    /// whole cells: its far corner is the pixel just before the grid corner.
    private func snappedShapeEnd(_ p: PixelPoint) -> PixelPoint {
        guard snapToGrid, tool == .rectangle || tool == .ellipse, let o = shapeOrigin else { return p }
        return PixelPoint(x: p.x > o.x ? p.x - 1 : p.x, y: p.y > o.y ? p.y - 1 : p.y)
    }

    func continueStroke(to p: PixelPoint, pressure: Double = 1) {
        continueStroke(through: [p], pressures: [pressure])
    }

    /// Extends the stroke through several points at once (all the Pencil
    /// samples of one touch event), redrawing the canvas only once.
    func continueStroke(through points: [PixelPoint], pressures: [Double]? = nil) {
        if selectionDrag != nil { return updateSelection(through: points) }
        let points = points.map(snapped)
        if sliceDrag != nil, let p = points.last { return continueSliceDrag(to: p) }
        if tileStroke {
            for p in points { placeTile(at: p) }
            return
        }
        guard strokeStart != nil, let target = points.last else { return }
        if pendingDragging {
            movePendingPoint(to: target)
            return
        }
        if tool.isShape {
            drawShape(to: snappedShapeEnd(target))
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
        if tool == .spray { return spray(at: points) }
        if tool == .contour { contourPath += path }
        plotFreehand(path, pressures: pathPressures)
    }

    func endStroke() {
        if selectionDrag != nil { return finishSelection() }
        if sliceDrag != nil { return endSliceDrag() }
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
        if start != storage {
            registerUndo(DocumentSnapshot(sprite: start, selection: selection))
            if tool.usesInk && !(useCustomBrush && tool.usesBrush && !customBrushUsesColor) { remember(primary) }
        }
        changed(.stroke)
    }

    /// The last colors painted with, newest first (the side panel's recent row).
    private(set) var recentColors: [PixelColor] = []
    static let recentColorCount = 8

    private func remember(_ color: PixelColor) {
        guard color.a > 0, recentColors.first != color else { return }
        recentColors.removeAll { $0 == color }
        recentColors.insert(color, at: 0)
        if recentColors.count > Self.recentColorCount { recentColors.removeLast() }
    }

    /// Reverts the stroke in progress, e.g. when a finger stroke turns out to be
    /// a pinch. While a curve or polygon is being built only the drag is undone.
    func cancelStroke() {
        if let drag = sliceDrag {
            sliceDrag = nil
            storage = drag.before
            changed()
            return
        }
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
        tileStroke = false
        gradientRegion = nil
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
        // Wrapped strokes can land anywhere.
        if tiledMode != .none { return .full(width: storage.width, height: storage.height) }
        let offsets = brushStamp(size: effectiveBrushSize).map(\.offset)
        let lower = min(0, offsets.map { min($0.x, $0.y) }.min() ?? 0)
        let upper = max(0, offsets.map { max($0.x, $0.y) }.max() ?? 0)
        guard var rect = PixelRect(bounding: points, lower: lower, upper: upper) else { return nil }
        rect = symmetry.covering(rect, width: storage.width, height: storage.height)
        return rect.clipped(width: storage.width, height: storage.height)
    }

    /// The ink a stroke uses: the eraser always erases.
    private var strokeInk: Ink { tool == .eraser ? .simple : ink }

    /// The custom brush, when it's the one in use for the current tool.
    private var activeCustomBrush: PixelImage? { useCustomBrush && tool.usesBrush ? customBrush : nil }
    /// The custom brush in use, if any (its size is its own: the size slider doesn't apply).
    var activeCustomBrushImage: PixelImage? { activeCustomBrush }

    /// The current brush at `size`: where it paints around the pointer, and the
    /// color of each pixel when the brush has its own (a custom brush).
    private func brushStamp(size: Int) -> [(offset: PixelPoint, color: PixelColor?)] {
        guard let brush = activeCustomBrush else {
            return Raster.brushOffsets(size: size, shape: brushShape, angle: brushAngle).map { ($0, nil) }
        }
        let cx = (brush.width - 1) / 2, cy = (brush.height - 1) / 2
        let tint = tool == .eraser || customBrushUsesColor
        var stamp: [(offset: PixelPoint, color: PixelColor?)] = []
        for y in 0..<brush.height {
            for x in 0..<brush.width where brush[x, y].a != 0 {
                var color = brush[x, y]
                if tint {
                    let a = color.a
                    color = strokeColor
                    color.a = UInt8(Int(color.a) * Int(a) / 255)
                }
                stamp.append((PixelPoint(x: x - cx, y: y - cy), tool == .eraser && color.a == 255 ? nil : color))
            }
        }
        return stamp
    }

    /// Stamps the brush on every point (and its mirror when symmetry is on).
    /// With a selection, only selected pixels are painted, as in Aseprite.
    /// `pressures` (0...1, one per point) scale the size and opacity when
    /// the pressure dynamics are on.
    private func stamp(_ points: [PixelPoint], pressures: [Double]? = nil, on image: inout PixelImage, color: PixelColor) {
        var stampsBySize: [Int: [(offset: PixelPoint, color: PixelColor?)]] = [:]
        func brush(_ size: Int) -> [(offset: PixelPoint, color: PixelColor?)] {
            if let cached = stampsBySize[size] { return cached }
            let stamp = brushStamp(size: size)
            stampsBySize[size] = stamp
            return stamp
        }
        var painter = makePainter(color: color)
        // A custom brush repaints its pixels on every stamp, so the last one shows.
        painter.repaints = activeCustomBrush != nil
        defer { strokeCoverage = painter.coverage }
        let brushSize = effectiveBrushSize
        let scalesSize = pressureSize && activeCustomBrush == nil
        for (n, p) in points.enumerated() {
            let pressure = pressures?[n] ?? 1
            let size = scalesSize ? 1 + Int((Double(brushSize - 1) * pressure).rounded()) : brushSize
            let alpha = pressureOpacity ? Double(toolOpacity) * pressure : Double(toolOpacity)
            let a = UInt8(max(1, min(255, alpha.rounded())))
            for (o, c) in brush(size) {
                let q = PixelPoint(x: p.x + o.x, y: p.y + o.y)
                painter.paint(q, alpha: a, color: c, on: &image)
                for m in symmetry.images(of: q, width: image.width, height: image.height) { painter.paint(m, alpha: a, color: c, on: &image) }
            }
        }
    }

    /// Spray: dots scattered at random around each sample.
    private func spray(at points: [PixelPoint]) {
        let r = sprayWidth
        let dirty = tiledMode != .none ? .full(width: storage.width, height: storage.height) : PixelRect(bounding: points, lower: -r, upper: r)
            .map { symmetry.covering($0, width: storage.width, height: storage.height) }?
            .clipped(width: storage.width, height: storage.height)
        let color = strokeColor, alpha = UInt8(max(1, min(255, toolOpacity))), count = spraySpeed
        mutateActiveCel(dirty: dirty) { image in
            var painter = makePainter(color: color)
            for p in points {
                for _ in 0..<count {
                    let angle = Double.random(in: 0..<(2 * .pi)), distance = Double.random(in: 0...1).squareRoot() * Double(r)
                    let q = PixelPoint(x: p.x + Int((cos(angle) * distance).rounded()), y: p.y + Int((sin(angle) * distance).rounded()))
                    painter.paint(q, alpha: alpha, on: &image)
                    for m in symmetry.images(of: q, width: image.width, height: image.height) { painter.paint(m, alpha: alpha, on: &image) }
                }
            }
            strokeCoverage = painter.coverage
        }
    }

    /// Makes a brush from the selected pixels of the active cel, as Aseprite's
    /// Edit > New Brush, and switches to the pencil to use it.
    func newBrushFromSelection() {
        guard let mask = selection, let bounds = mask.bounds else { return }
        let cel = storage.cels[activeCelKey] ?? PixelImage(width: storage.width, height: storage.height)
        var image = cel.cropped(to: bounds)
        let local = mask.cropped(to: bounds)
        for i in image.pixels.indices where !local.bits[i] { image.pixels[i] = .clear }
        guard let content = SelectionMask.opaquePixels(of: image).bounds else {
            notice = L10n.string("There's nothing drawn in the selection")
            return
        }
        customBrush = image.cropped(to: content)
        useCustomBrush = true
        deselect()
        select(.pencil)
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
            ramp: storage.palette.filter { !$0.isTransparent }, direction: shadeDirection, tiling: tiledMode, coverage: coverage
        )
    }

    private func plotFreehand(_ points: [PixelPoint], pressures: [Double]? = nil) {
        let color = strokeColor
        let usePixelPerfect = pixelPerfect && brushSize == 1 && activeCustomBrush == nil && (tool == .pencil || tool == .eraser)
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
        guard isCorner, !strokePath[..<(n - 3)].contains(b) else { return }
        func restore(_ point: PixelPoint) {
            let q = tiledMode.wrap(point, width: image.width, height: image.height)
            guard image.contains(q) else { return }
            image[q] = original?[q] ?? .clear
            if strokeCoverage.indices.contains(q.y * image.width + q.x) { strokeCoverage[q.y * image.width + q.x] = 0 }
        }
        restore(b)
        for m in symmetry.images(of: b, width: image.width, height: image.height) { restore(m) }
        strokePath.remove(at: n - 2)
    }

    private func drawShape(to p: PixelPoint) {
        guard let origin = shapeOrigin else { return }
        switch tool {
        case .line: drawPreview(Raster.line(from: origin, to: p))
        case .rectangle: drawPreview(Raster.rectangle(from: origin, to: p, filled: shapeFilled, radius: cornerRadius))
        case .ellipse: drawPreview(Raster.ellipse(from: origin, to: p, filled: shapeFilled))
        case .gradient: drawGradient(from: origin, to: p)
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

    /// The area the paint bucket (and the gradient) reaches from `p`, with the bucket's options.
    private func bucketRegion(at p: PixelPoint) -> SelectionMask {
        let reference = fillSampleAllLayers
            ? storage.composite(frameIndex: activeFrameIndex)
            : storage.cels[activeCelKey] ?? PixelImage(width: storage.width, height: storage.height)
        var bounds = selection
        if fillStopsAtGrid, let cell = storage.grid.cell(containing: p).clipped(width: storage.width, height: storage.height) {
            let inCell = SelectionMask.rect(cell, width: storage.width, height: storage.height)
            bounds = bounds.map { $0.combined(with: inCell, mode: .intersect) } ?? inCell
        }
        return Raster.fillRegion(
            in: reference, at: p, tolerance: fillTolerance, contiguous: fillContiguous,
            diagonal: fillDiagonal, within: bounds
        )
    }

    /// Paints the gradient over its area, from the cel as the drag found it.
    private func drawGradient(from a: PixelPoint, to b: PixelPoint) {
        guard let region = gradientRegion, let bounds = region.bounds else { return }
        let gradient = Gradient(from: primary, to: secondary, a: a, b: b, shape: gradientShape, dither: gradientDither)
        let alpha = UInt8(max(1, min(255, toolOpacity)))
        mutateActiveCel(dirty: bounds) { image in
            strokeCoverage = [UInt8](repeating: 0, count: image.width * image.height)
            var painter = makePainter(color: primary)
            for y in bounds.minY...bounds.maxY {
                for x in bounds.minX...bounds.maxX where region[x, y] {
                    let q = PixelPoint(x: x, y: y)
                    painter.paint(q, alpha: alpha, color: gradient.color(at: q), on: &image)
                }
            }
            strokeCoverage = painter.coverage
        }
    }

    /// Paint bucket: paints the area it reaches with the ink and opacity.
    private func fill(at p: PixelPoint) {
        let region = bucketRegion(at: p)
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

    // MARK: Slices

    /// The active slice's shape on the active frame.
    var activeSliceKey: SliceKey? {
        guard let slice = structure.slices.first(where: { $0.id == activeSliceID }) else { return nil }
        return slice.key(at: activeFrameIndex, frames: structure.frames)
    }

    /// Slice tool: touching the active slice's edge resizes it, inside it
    /// moves it, inside another slice picks that one, elsewhere draws a new one.
    private func beginSliceDrag(at p: PixelPoint) {
        let frames = storage.frames
        let hit = storage.slices.reversed().first { $0.key(at: activeFrameIndex, frames: frames)?.bounds.contains(p) == true }
        if let active = storage.slices.first(where: { $0.id == activeSliceID }),
           let bounds = active.key(at: activeFrameIndex, frames: frames)?.bounds,
           bounds.insetBy(-1).contains(p) {
            let edges = SliceEdges(p, bounds)
            sliceDrag = (active.id, p, bounds, edges, storage)
            return
        }
        if let hit, let bounds = hit.key(at: activeFrameIndex, frames: frames)?.bounds {
            activeSliceID = hit.id
            sliceDrag = (hit.id, p, bounds, .all, storage)
            return
        }
        let before = storage
        let names = Set(storage.slices.map(\.name))
        var n = storage.slices.count + 1
        while names.contains(L10n.string("Slice %d", n)) { n += 1 }
        let color = Slice.colors[storage.slices.count % Slice.colors.count]
        let bounds = PixelRect(minX: p.x, minY: p.y, maxX: p.x, maxY: p.y)
        let slice = Slice(name: L10n.string("Slice %d", n), color: color, keys: [SliceKey(frame: frames[0].id, bounds: bounds)])
        storage.slices.append(slice)
        activeSliceID = slice.id
        sliceDrag = (slice.id, p, bounds, .drawing, before)
        onOverlayChange?()
    }

    private func continueSliceDrag(to p: PixelPoint) {
        guard let drag = sliceDrag else { return }
        var b = drag.bounds
        // Snap to grid: new slices take whole cells, moves and resizes go cell by cell.
        let raw = (Double(p.x - drag.start.x), Double(p.y - drag.start.y))
        let (sdx, sdy) = snapToGrid ? storage.grid.snap(dx: raw.0, dy: raw.1) : raw
        let dx = Int(sdx), dy = Int(sdy)
        switch drag.edges {
        case .drawing:
            b = snapToGrid
                ? storage.grid.cells(from: drag.start, to: p)
                : PixelRect(minX: min(drag.start.x, p.x), minY: min(drag.start.y, p.y), maxX: max(drag.start.x, p.x), maxY: max(drag.start.y, p.y))
        case .all:
            b = b.offsetBy(dx: dx, dy: dy)
        default:
            if drag.edges.contains(.left) { b.minX = min(b.maxX, b.minX + dx) }
            if drag.edges.contains(.right) { b.maxX = max(b.minX, b.maxX + dx) }
            if drag.edges.contains(.top) { b.minY = min(b.maxY, b.minY + dy) }
            if drag.edges.contains(.bottom) { b.maxY = max(b.minY, b.maxY + dy) }
        }
        updateSliceKey(drag.slice, in: &storage) { $0.bounds = b }
        onOverlayChange?()
    }

    private func endSliceDrag() {
        guard let drag = sliceDrag else { return }
        sliceDrag = nil
        // A tap on empty canvas only deselects; slices are drawn by dragging.
        if drag.edges == .drawing, activeSliceKey.map({ $0.bounds.width == 1 && $0.bounds.height == 1 }) ?? false {
            storage = drag.before
            activeSliceID = nil
            changed()
            return
        }
        if drag.before != storage { registerUndo(DocumentSnapshot(sprite: drag.before, selection: selection)) }
        changed()
    }

    /// Changes the slice's key on the active frame, adding one there (from the
    /// shape it had) when the change is on a later frame, as in Aseprite.
    private func updateSliceKey(_ id: UUID, in sprite: inout Sprite, _ change: (inout SliceKey) -> Void) {
        guard let i = sprite.slices.firstIndex(where: { $0.id == id }),
              var key = sprite.slices[i].key(at: activeFrameIndex, frames: sprite.frames) else { return }
        let frame = sprite.frames[activeFrameIndex].id
        change(&key)
        if let k = sprite.slices[i].keys.firstIndex(where: { $0.frame == frame }) {
            sprite.slices[i].keys[k] = key
        } else {
            key.frame = frame
            sprite.slices[i].keys.append(key)
        }
    }

    func editActiveSlice(_ change: @escaping (inout SliceKey) -> Void) {
        guard let id = activeSliceID else { return }
        perform { s in self.updateSliceKey(id, in: &s, change) }
    }

    func renameSlice(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        perform { s in if let i = s.slices.firstIndex(where: { $0.id == id }) { s.slices[i].name = trimmed } }
    }

    func setSliceColor(_ id: UUID, _ color: PixelColor) {
        perform { s in if let i = s.slices.firstIndex(where: { $0.id == id }) { s.slices[i].color = color } }
    }

    func deleteSlice(_ id: UUID) {
        perform { $0.slices.removeAll { $0.id == id } }
        if activeSliceID == id { activeSliceID = nil }
    }

    /// View > Grid Settings. Part of the sprite, so it's undoable and saved.
    func setGrid(_ grid: GridSettings) {
        var g = grid
        g.width = max(1, min(storage.width, g.width))
        g.height = max(1, min(storage.height, g.height))
        perform { $0.grid = g }
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

    /// "Layer N" with the first N no layer uses yet.
    private func newLayerName() -> String {
        let names = Set(sprite.layers.map(\.name))
        var n = sprite.layers.count + 1
        func layerName(_ n: Int) -> String { L10n.string("Layer %d", n) }
        while names.contains(layerName(n)) { n += 1 }
        return layerName(n)
    }

    /// A new layer above the active one, in its group (or, on a group, inside it on top).
    func addLayer() {
        var layer = Layer(name: newLayerName())
        let index = sprite.layers.firstIndex { $0.id == activeLayerID } ?? sprite.layers.count - 1
        let active = sprite.layers.indices.contains(index) ? sprite.layers[index] : nil
        layer.parent = active?.isGroup == true ? active?.id : active?.parent
        perform { $0.layers.insert(layer, at: active?.isGroup == true ? index : index + 1) }
        activeLayerID = layer.id
    }

    /// An image or animated GIF as a new layer above the active one: one GIF
    /// frame per timeline frame from the active frame on, adding the frames it
    /// needs (with the GIF's durations). An image of another size is centered
    /// and cropped. One undo step.
    @discardableResult
    func importLayer(imageData data: Data, name: String) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            notice = L10n.string("That image can't be opened")
            return false
        }
        var images: [(image: PixelImage, duration: Int?)] = []
        for index in 0..<CGImageSourceGetCount(source) {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil), let image = PixelImage(cgImage: cgImage) else { continue }
            let duration = DocumentStore.frameDelay(source, at: index).map { max(10, Int(($0 * 1000).rounded())) }
            images.append((image, duration))
        }
        guard !images.isEmpty else {
            notice = L10n.string("That image can't be opened")
            return false
        }
        stopPlayback()
        applyTransformIfNeeded()
        let (w, h) = (storage.width, storage.height)
        var layer = Layer(name: name)
        let index = sprite.layers.firstIndex { $0.id == activeLayerID } ?? sprite.layers.count - 1
        let active = sprite.layers.indices.contains(index) ? sprite.layers[index] : nil
        layer.parent = active?.isGroup == true ? active?.id : active?.parent
        let start = activeFrameIndex
        perform { s in
            s.layers.insert(layer, at: active?.isGroup == true ? index : index + 1)
            for (offset, item) in images.enumerated() {
                let frame = start + offset
                if frame >= s.frames.count { s.insertFrame(Frame(duration: item.duration ?? s.frames.last?.duration ?? 100), at: s.frames.count) }
                var cel = PixelImage(width: w, height: h)
                let ox = (w - item.image.width) / 2, oy = (h - item.image.height) / 2
                for y in 0..<item.image.height where (0..<h).contains(y + oy) {
                    for x in 0..<item.image.width where (0..<w).contains(x + ox) {
                        cel[x + ox, y + oy] = item.image[x, y]
                    }
                }
                if !cel.isEmpty { s.cels[CelKey(layer: layer.id, frame: s.frames[frame].id)] = cel }
            }
        }
        activeLayerID = layer.id
        return true
    }

    /// A tap on the timeline's projected cells: empty frames are added up to
    /// `frame` (an index) and `layersBelow` new layers under the bottom one, as
    /// one undo step, and the tapped cell becomes the active one.
    func extendTimeline(toFrame frame: Int?, layersBelow: Int, layer: UUID? = nil) {
        let addedFrames = max(0, (frame ?? 0) + 1 - sprite.frames.count)
        guard addedFrames > 0 || layersBelow > 0 else {
            if let layer { activeLayerID = layer }
            if let frame { goToFrame(frame) }
            return
        }
        var names = Set(sprite.layers.map(\.name))
        var newLayers: [Layer] = []
        for _ in 0..<layersBelow {
            var n = sprite.layers.count + newLayers.count + 1
            while names.contains(L10n.string("Layer %d", n)) { n += 1 }
            let name = L10n.string("Layer %d", n)
            names.insert(name)
            newLayers.append(Layer(name: name))
        }
        perform { s in
            let duration = s.frames.last?.duration ?? 100
            for _ in 0..<addedFrames { s.insertFrame(Frame(duration: duration), at: s.frames.count) }
            // Under the bottom layer, but never below the background.
            let bottom = s.layers.first?.isBackground == true ? 1 : 0
            s.layers.insert(contentsOf: newLayers.reversed(), at: bottom)
        }
        if let last = newLayers.last { activeLayerID = last.id } else if let layer { activeLayerID = layer }
        if let frame { goToFrame(frame) }
    }

    /// Deletes a layer; a group goes with everything in it.
    func deleteLayer(_ id: UUID) {
        let removed = Set([id] + sprite.descendants(of: id).map(\.id))
        let remaining = sprite.layers.filter { !removed.contains($0.id) }
        guard remaining.contains(where: { !$0.isGroup }), let index = sprite.layers.firstIndex(where: { $0.id == id }) else { return }
        if removed.contains(activeLayerID) {
            let below = sprite.layers[..<index].last { !removed.contains($0.id) }
            activeLayerID = (below ?? remaining.first!).id
        }
        perform { s in
            s.layers.removeAll { removed.contains($0.id) }
            s.cels = s.cels.filter { !removed.contains($0.key.layer) }
            s.normalizeLinks()
        }
    }

    func setBlendMode(_ mode: BlendMode, layer id: UUID) {
        updateLayer(id) { $0.blendMode = mode }
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
            // The background lives at the bottom, outside any group.
            s.layers[index].parent = nil
            s.keepBackgroundAtBottom()
        }
    }

    /// Layer > Convert To > Layer: the background becomes a regular transparent layer.
    func convertToLayer(_ id: UUID) {
        updateLayer(id) { $0.isBackground = false }
    }

    /// Whether `moveLayer(_:by:)` has somewhere to go: a neighbour in the same
    /// group, and never below the background.
    func canMoveLayer(_ id: UUID, by offset: Int) -> Bool {
        let layers = structure.layers
        guard let layer = layers.first(where: { $0.id == id }), !layer.isBackground else { return false }
        let siblings = layers.filter { $0.parent == layer.parent }
        guard let index = siblings.firstIndex(where: { $0.id == id }), siblings.indices.contains(index + offset) else { return false }
        return !siblings[index + offset].isBackground
    }

    /// Positive `offset` moves the layer up (towards the top of the stack),
    /// past its neighbours in the same group; a group moves with its children.
    func moveLayer(_ id: UUID, by offset: Int) {
        guard let layer = sprite.layers.first(where: { $0.id == id }) else { return }
        let siblings = sprite.layers.filter { $0.parent == layer.parent }
        guard let index = siblings.firstIndex(where: { $0.id == id }), siblings.indices.contains(index + offset) else { return }
        let other = siblings[index + offset].id
        perform { s in
            // Swap the two siblings' places; normalizing brings their children along.
            guard let a = s.layers.firstIndex(where: { $0.id == id }), let b = s.layers.firstIndex(where: { $0.id == other }) else { return }
            s.layers.swapAt(a, b)
            s.normalizeGroups()
            s.keepBackgroundAtBottom()
        }
    }

    /// Moves a layer to the stack position currently held by `target` (drag
    /// and drop), into `target`'s group.
    func moveLayer(_ id: UUID, to target: UUID) {
        guard id != target,
              let from = sprite.layers.firstIndex(where: { $0.id == id }),
              let to = sprite.layers.firstIndex(where: { $0.id == target }),
              !sprite.descendants(of: id).contains(where: { $0.id == target }) else { return }
        perform { s in
            var layer = s.layers.remove(at: from)
            layer.parent = s.layers.first { $0.id == target }?.parent
            s.layers.insert(layer, at: to)
            s.normalizeGroups()
            s.keepBackgroundAtBottom()
        }
    }

    // MARK: Arrange

    /// The layers Arrange moves: those the transform or the selection is on, or the active one.
    private var arrangeTargets: [UUID] {
        if let layer = floating?.celKey.layer { return [layer] }
        if let layers = selectionLayers { return sprite.layers.map(\.id).filter { layers.contains($0) } }
        return [activeLayerID]
    }

    /// Whether Arrange can move the selected element up (towards the front) or down.
    func canArrange(forward: Bool) -> Bool {
        arrangeTargets.contains { canMoveLayer($0, by: forward ? 1 : -1) }
    }

    /// Bring to front, bring forward, send backward or send to back: what's
    /// selected goes above or below the other layers. Each part lives on its
    /// own layer, so this moves its layer in the stack, for every frame.
    /// While transforming it stays part of the transform's undo step.
    func arrange(_ arrangement: LayerArrangement) {
        let up = arrangement == .front || arrangement == .forward
        let steps = arrangement == .forward || arrangement == .backward ? 1 : sprite.layers.count
        // The one in front moves first going up, the one behind going down, so they keep their order.
        let ids = up ? arrangeTargets.reversed() : arrangeTargets
        func move(_ s: inout Sprite) {
            for id in ids {
                for _ in 0..<steps {
                    guard let layer = s.layers.first(where: { $0.id == id }), !layer.isBackground else { break }
                    let siblings = s.layers.filter { $0.parent == layer.parent }
                    guard let index = siblings.firstIndex(where: { $0.id == id }),
                          siblings.indices.contains(index + (up ? 1 : -1)) else { break }
                    let other = siblings[index + (up ? 1 : -1)]
                    guard !other.isBackground, !ids.contains(other.id),
                          let a = s.layers.firstIndex(where: { $0.id == id }),
                          let b = s.layers.firstIndex(where: { $0.id == other.id }) else { break }
                    s.layers.swapAt(a, b)
                    s.normalizeGroups()
                    s.keepBackgroundAtBottom()
                }
            }
        }
        if isTransforming {
            var s = storage
            move(&s)
            guard s != storage else { return }
            storage = s
            changed()
        } else {
            perform(move)
        }
    }

    // MARK: Groups

    /// Layer > New > Group: a group around the active layer.
    func groupActiveLayer() { groupLayers([activeLayerID]) }

    /// Puts `ids` in a new group placed where the topmost of them was.
    func groupLayers(_ ids: [UUID]) {
        let members = sprite.layers.filter { ids.contains($0.id) && !$0.isBackground }
        guard let top = members.last else { return }
        let names = Set(sprite.layers.map(\.name))
        var n = sprite.layers.filter(\.isGroup).count + 1
        while names.contains(L10n.string("Group %d", n)) { n += 1 }
        var group = Layer(name: L10n.string("Group %d", n))
        group.isGroup = true
        group.parent = top.parent
        let memberIDs = Set(members.map(\.id))
        perform { s in
            for i in s.layers.indices where memberIDs.contains(s.layers[i].id) { s.layers[i].parent = group.id }
            guard let index = s.layers.firstIndex(where: { $0.id == top.id }) else { return }
            s.layers.insert(group, at: index + 1)
            s.normalizeGroups()
        }
        activeLayerID = group.id
    }

    /// Moves a layer into `group`, on top of its children.
    func moveIntoGroup(_ id: UUID, group: UUID) {
        guard id != group, !sprite.descendants(of: id).contains(where: { $0.id == group }) else { return }
        perform { s in
            guard let from = s.layers.firstIndex(where: { $0.id == id }) else { return }
            var layer = s.layers.remove(at: from)
            layer.parent = group
            guard let to = s.layers.firstIndex(where: { $0.id == group }) else { return }
            s.layers.insert(layer, at: to)
            s.normalizeGroups()
        }
    }

    /// Takes a layer out of its group, just above it.
    func removeFromGroup(_ id: UUID) {
        guard let layer = sprite.layers.first(where: { $0.id == id }), let groupID = layer.parent else { return }
        let outer = sprite.layers.first { $0.id == groupID }?.parent
        perform { s in
            guard let from = s.layers.firstIndex(where: { $0.id == id }) else { return }
            var moved = s.layers.remove(at: from)
            moved.parent = outer
            guard let to = s.layers.firstIndex(where: { $0.id == groupID }) else { return }
            s.layers.insert(moved, at: to + 1)
            s.normalizeGroups()
        }
    }

    /// Removes a group, keeping its layers where they are.
    func ungroup(_ id: UUID) {
        guard let group = sprite.layers.first(where: { $0.id == id && $0.isGroup }) else { return }
        let firstChild = sprite.layers.first { $0.parent == id }?.id
        perform { s in
            for i in s.layers.indices where s.layers[i].parent == id { s.layers[i].parent = group.parent }
            s.layers.removeAll { $0.id == id }
            s.normalizeGroups()
        }
        if activeLayerID == id, let firstChild { activeLayerID = firstChild }
    }

    /// Shows or hides a group's children in the timeline. A view setting: not an undo step.
    func toggleExpanded(_ id: UUID) {
        guard let index = storage.layers.firstIndex(where: { $0.id == id }) else { return }
        storage.layers[index].isExpanded.toggle()
        revision &+= 1
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

    var activeTag: FrameTag? { structure.tag(containing: activeFrameIndex) }

    // MARK: - Palette

    func addToPalette(_ color: PixelColor) {
        guard !sprite.palette.contains(color), sprite.palette.count < PaletteFile.maxColors else { return }
        perform { $0.palette.append(color) }
    }

    func removeFromPalette(at index: Int) {
        guard sprite.palette.indices.contains(index) else { return }
        perform { $0.palette.remove(at: index) }
    }

    /// Palette > New empty palette: no colors, to build one with +. Pixels don't change.
    func clearPalette() {
        guard !sprite.palette.isEmpty else { return }
        perform { $0.palette = [] }
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
        guard sprite.palette.indices.contains(range.upperBound) else { return }
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
    func paletteIndex(of color: PixelColor) -> Int? { structure.palette.firstIndex(of: color) }

    // MARK: - Replace color

    /// Edit > Replace Color: pixels within `tolerance` of `from` become `to`,
    /// in the active cel or in every cel, inside the selection if there is one.
    /// Locked layers are left alone. Returns how many pixels changed (linked cels count once each).
    @discardableResult
    func replaceColor(_ from: PixelColor, with to: PixelColor, tolerance: Int, everyCel: Bool) -> Int {
        applyTransformIfNeeded()
        let mask = selection
        let editable = Set(sprite.layers.filter { !sprite.locks($0) }.map(\.id))
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

    // MARK: - Hue/Saturation

    /// The sprite as it was when the Hue/Saturation panel opened; the sliders preview on a copy of it.
    private var adjustmentBase: DocumentSnapshot?
    var isAdjustingHueSaturation: Bool { adjustmentBase != nil }

    /// Edit > Adjustments > Hue/Saturation (⌘U): opens the panel.
    func beginHueSaturation() {
        guard adjustmentBase == nil else { return }
        applyTransformIfNeeded()
        stopPlayback()
        endOutline(apply: nil, everyCel: false)
        adjustmentBase = DocumentSnapshot(sprite: storage, selection: selection)
        isShowingColorShading = false
    }

    /// Shows or hides Color Shading. Showing it closes Hue/Saturation without applying it.
    func toggleColorShading() {
        if isShowingColorShading {
            isShowingColorShading = false
        } else {
            endHueSaturation(apply: nil, everyCel: false)
            endOutline(apply: nil, everyCel: false)
            isShowingColorShading = true
        }
    }

    /// Shows the adjustment on the canvas without committing it.
    func previewHueSaturation(_ adjustment: HueSaturation, everyCel: Bool) {
        guard let base = adjustmentBase else { return }
        var adjusted = base.sprite
        applyHueSaturation(adjustment, everyCel: everyCel, to: &adjusted)
        guard adjusted != storage else { return }
        storage = adjusted
        revision &+= 1
    }

    /// Applies the adjustment as one undoable step, or puts the pixels back.
    func endHueSaturation(apply adjustment: HueSaturation?, everyCel: Bool) {
        guard let base = adjustmentBase else { return }
        adjustmentBase = nil
        storage = base.sprite
        guard let adjustment, !adjustment.isIdentity else {
            revision &+= 1
            return
        }
        var adjusted = base.sprite
        if applyHueSaturation(adjustment, everyCel: everyCel, to: &adjusted) == 0 {
            notice = L10n.string("The layer is locked")
        }
        guard adjusted != base.sprite else {
            revision &+= 1
            return
        }
        registerUndo(base)
        storage = adjusted
        changed()
    }

    /// The active cel, or every cel, inside the selection if there is one; locked layers
    /// are left alone. Returns how many cels it could change.
    @discardableResult
    private func applyHueSaturation(_ adjustment: HueSaturation, everyCel: Bool, to s: inout Sprite) -> Int {
        let editable = Set(s.layers.filter { !s.locks($0) && !$0.isReference }.map(\.id))
        let keys = everyCel ? s.cels.keys.filter { editable.contains($0.layer) } : (editable.contains(activeLayerID) ? [activeCelKey] : [])
        guard !adjustment.isIdentity else { return keys.count }
        let mask = selection
        // Each color is worked out once.
        var cache: [PixelColor: PixelColor] = [:]
        for key in keys {
            guard var cel = s.cels[key] else { continue }
            for i in cel.pixels.indices where cel.pixels[i].a != 0 && (mask?.bits[i] ?? true) {
                let c = cel.pixels[i]
                if let done = cache[c] { cel.pixels[i] = done; continue }
                let out = adjustment.apply(c)
                cache[c] = out
                cel.pixels[i] = out
            }
            s.cels[key] = cel.isEmpty ? nil : cel
            if !everyCel { s.syncLinks(from: key) }
        }
        return keys.count
    }

    // MARK: - Outline

    /// The sprite as it was when the Outline window opened; the preview draws on a copy of it.
    private var outlineBase: DocumentSnapshot?
    var isOutlining: Bool { outlineBase != nil }
    /// Whether an effect window is open: drawing waits until it's applied or cancelled.
    var isAdjusting: Bool { isAdjustingHueSaturation || isOutlining }

    /// Edit > FX > Outline: opens the window.
    func beginOutline() {
        guard outlineBase == nil else { return }
        endHueSaturation(apply: nil, everyCel: false)
        applyTransformIfNeeded()
        stopPlayback()
        outlineBase = DocumentSnapshot(sprite: storage, selection: selection)
        isShowingColorShading = false
    }

    /// Shows the outline on the canvas without committing it.
    func previewOutline(_ effect: OutlineEffect, everyCel: Bool) {
        guard let base = outlineBase else { return }
        var outlined = base.sprite
        applyOutline(effect, everyCel: everyCel, to: &outlined)
        guard outlined != storage else { return }
        storage = outlined
        revision &+= 1
    }

    /// Draws the outline as one undoable step, or puts the pixels back.
    func endOutline(apply effect: OutlineEffect?, everyCel: Bool) {
        guard let base = outlineBase else { return }
        outlineBase = nil
        storage = base.sprite
        guard let effect else {
            revision &+= 1
            return
        }
        var outlined = base.sprite
        if applyOutline(effect, everyCel: everyCel, to: &outlined) == 0 {
            notice = L10n.string("The layer is locked")
        }
        guard outlined != base.sprite else {
            revision &+= 1
            return
        }
        registerUndo(base)
        storage = outlined
        changed()
    }

    /// The active cel, the cels picked in the timeline, or every cel, inside the
    /// selection if there is one; locked layers are left alone. Returns how many
    /// cels it could change.
    @discardableResult
    private func applyOutline(_ effect: OutlineEffect, everyCel: Bool, to s: inout Sprite) -> Int {
        let editable = Set(s.layers.filter { !s.locks($0) && !$0.isReference && !$0.isTilemap }.map(\.id))
        let keys: [CelKey]
        if everyCel {
            keys = s.layers.filter { editable.contains($0.id) }.flatMap { layer in s.frames.map { CelKey(layer: layer.id, frame: $0.id) } }
        } else if let range = timelineRange {
            keys = rangeKeys(range).flatMap { $0 }.filter { editable.contains($0.layer) }
        } else {
            keys = editable.contains(activeLayerID) ? [activeCelKey] : []
        }
        let mask = selection
        // Linked cels share one image: outline it once, or it would grow a ring per cel.
        var doneGroups = Set<UUID>()
        for key in keys {
            if let group = s.links[key] {
                guard doneGroups.insert(group).inserted else { continue }
            }
            let cel = s.cels[key] ?? PixelImage(width: s.width, height: s.height)
            let outlined = effect.apply(to: cel, mask: mask)
            guard outlined != cel else { continue }
            s.cels[key] = outlined.isEmpty ? nil : outlined
            s.syncLinks(from: key)
        }
        return keys.count
    }

    // MARK: - Playback

    func togglePlayback() {
        if isPlaying {
            stopPlayback()
            // Preferences > Rewind on stop: back to where playback started.
            if EditorSettings.rewindOnStop, let start = playbackStartFrame, start < sprite.frames.count { activeFrameIndex = start }
        } else {
            playbackStartFrame = activeFrameIndex
            startPlayback()
        }
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
        // Every stroke stops playback; only notify when it was actually playing.
        if isPlaying { isPlaying = false }
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
            if snapToGrid {
                let r = storage.grid.cells(from: drag.start, to: p)
                shape = .ellipse(from: PixelPoint(x: r.minX, y: r.minY), to: PixelPoint(x: r.maxX, y: r.maxY), width: storage.width, height: storage.height)
            } else {
                shape = .ellipse(from: drag.start, to: p, width: storage.width, height: storage.height)
            }
        case .lasso:
            for q in points where q != lassoPath.last { lassoPath.append(q) }
            shape = .polygon(lassoPath, width: storage.width, height: storage.height)
        default:
            let rect = snapToGrid
                ? storage.grid.cells(from: drag.start, to: p)
                : PixelRect(minX: min(drag.start.x, p.x), minY: min(drag.start.y, p.y), maxX: max(drag.start.x, p.x), maxY: max(drag.start.y, p.y))
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
        for layer in storage.layers.reversed() where storage.shows(layer) && !layer.isBackground && !storage.locks(layer) {
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
            return (storage.layers.filter { r.layers.contains($0.id) && storage.shows($0) && !$0.isBackground && !storage.locks($0) },
                    r.frames.compactMap { storage.frames.indices.contains($0) ? storage.frames[$0].id : nil })
        }
        return (storage.layers.filter { storage.shows($0) && !$0.isBackground && !storage.locks($0) },
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
        if layer.isGroup { notice = L10n.string("“%@” is a group: pick a layer inside it to draw", layer.name); return false }
        if !storage.shows(layer) { notice = L10n.string("Layer “%@” is hidden", layer.name); return false }
        if storage.locks(layer) { notice = L10n.string("Layer “%@” is locked", layer.name); return false }
        if layer.isReference { notice = L10n.string("“%@” is a reference layer: use the Move tool to place it", layer.name); return false }
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
        let editable = Set(storage.layers.filter { storage.shows($0) && !storage.locks($0) }.map(\.id))
        let result = keys.filter { editable.contains($0.layer) }
        if result.isEmpty { notice = L10n.string("The layers are hidden or locked") }
        return result
    }

    // MARK: Selection opacity

    /// The rail's selection opacity slider: the pixels before it was first
    /// moved for this selection, and how much of their opacity is left. It
    /// lasts while nothing else changes the sprite or the selection, so the
    /// slider keeps showing where it was left.
    struct SelectionFade {
        var base: Sprite
        var selection: SelectionMask?
        var keys: [CelKey]
        var factor: Double
        var revision: Int
    }

    /// How much of the selected pixels' opacity the slider has left (1 = untouched).
    var selectionOpacity: Double {
        _ = revision
        guard let fade = selectionFade, fade.selection == selection, fade.revision == revision else { return 1 }
        return fade.factor
    }

    /// Starts a drag of the slider.
    func beginSelectionOpacity() {
        guard selection != nil, !isTransforming else { return }
        if selectionFade.map({ $0.selection != selection || $0.revision != revision }) ?? true {
            let keys = selectionEditKeys
            guard !keys.isEmpty else { return }
            selectionFade = SelectionFade(base: storage, selection: selection, keys: keys, factor: 1, revision: revision)
        }
        selectionFadeStart = DocumentSnapshot(sprite: storage, selection: selection)
    }

    /// Sets the selected pixels' opacity to `factor` of what it was, live.
    func setSelectionOpacity(_ factor: Double) {
        guard var fade = selectionFade, selectionFadeStart != nil, let mask = fade.selection else { return }
        let f = min(1, max(0, factor))
        var s = fade.base
        for key in fade.keys {
            guard var cel = s.cels[key] else { continue }
            for i in cel.pixels.indices where mask.bits[i] && cel.pixels[i].a != 0 {
                cel.pixels[i].a = UInt8((Double(cel.pixels[i].a) * f).rounded())
            }
            s.cels[key] = cel.isEmpty ? nil : cel
            s.syncLinks(from: key)
        }
        storage = s
        revision &+= 1
        fade.factor = f
        fade.revision = revision
        selectionFade = fade
    }

    /// Ends the drag: one undo step for it.
    func endSelectionOpacity() {
        guard let start = selectionFadeStart else { return }
        selectionFadeStart = nil
        guard start.sprite != storage else { return }
        registerUndo(start)
        changed()
        selectionFade?.revision = revision
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
    /// goes to the active layer, so the layers stay apart. Cels picked in the
    /// timeline only recolor what they have, so every frame changes alike.
    func fillSelection() {
        let keys = selectionEditKeys
        guard !keys.isEmpty else { return }
        let mask = selection, color = primary
        let active: CelKey? = timelineRange != nil && keys.count > 1 ? nil : activeCelKey
        let (w, h) = (storage.width, storage.height)
        perform { s in
            // Pixels drawn in any of the layers of a frame: those stay with their own layer.
            var drawn: [UUID: [Bool]] = [:]
            if keys.count > 1 {
                for key in keys {
                    var bits = drawn[key.frame] ?? [Bool](repeating: false, count: w * h)
                    if let cel = s.cels[key] { for i in cel.pixels.indices where cel.pixels[i].a != 0 { bits[i] = true } }
                    drawn[key.frame] = bits
                }
            }
            for key in keys {
                var cel = s.cels[key] ?? PixelImage(width: w, height: h)
                let isActive = keys.count == 1 || key == active
                let drawn = drawn[key.frame] ?? []
                for i in cel.pixels.indices where mask?.bits[i] ?? true {
                    let own = cel.pixels[i].a != 0
                    guard own || (isActive && !(drawn.indices.contains(i) && drawn[i])) else { continue }
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
        let locked = Set(storage.layers.filter { storage.locks($0) }.map(\.id))
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
            let cel = Self.stamp(rendered(&item.floating), onto: item.base)
            let result: PixelImage? = cel.isEmpty ? nil : cel
            for key in [item.floating.celKey] + item.linked { storage.cels[key] = result }
        }
        rangeFloating = []
        transformExtraCels = 0
    }

    private func rendered(_ f: inout FloatingSelection) -> (image: PixelImage, origin: PixelPoint, mask: SelectionMask) {
        stretchMove
            ? f.renderStretched(spriteWidth: storage.width, spriteHeight: storage.height)
            : f.render(spriteWidth: storage.width, spriteHeight: storage.height)
    }

    /// Draws the floating pixels over the cel they were lifted from.
    private func renderFloating() {
        guard var f = floating, let base = floatingBase else { return }
        let rendered = self.rendered(&f)
        floating = f
        storage.cels[f.celKey] = Self.stamp(rendered, onto: base)
        // The other layers of a multi-layer selection follow live in this frame;
        // other frames of a timeline range change when the transform is applied.
        for i in rangeFloating.indices where rangeFloating[i].floating.celKey.frame == f.celKey.frame {
            rangeFloating[i].floating.box = f.box
            let other = self.rendered(&rangeFloating[i].floating)
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
        stretchMove = false
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
        stretchMove = false
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
        // The Move tool on a reference layer moves its image.
        if !isTransforming, let layer = activeLayer, let reference = layer.reference {
            guard !layer.isLocked else { notice = L10n.string("Layer “%@” is locked", layer.name); return }
            referenceDrag = (layer.id, point, reference.frame, storage)
            return
        }
        if !isTransforming { beginTransform() }
        guard let box = floating?.box else { return }
        transformDrag = (handle, point, box)
    }

    func continueTransformDrag(to point: CGPoint) {
        if let drag = referenceDrag {
            let moved = drag.frame.offsetBy(dx: (point.x - drag.start.x).rounded(), dy: (point.y - drag.start.y).rounded())
            if let i = storage.layers.firstIndex(where: { $0.id == drag.layer }) { storage.layers[i].reference?.frame = moved }
            revision &+= 1
            return
        }
        guard let drag = transformDrag, var f = floating else { return }
        var box = drag.box
        switch drag.handle {
        case .move:
            let (dx, dy) = snapToGrid
                ? storage.grid.snap(dx: point.x - drag.start.x, dy: point.y - drag.start.y)
                : ((point.x - drag.start.x).rounded(), (point.y - drag.start.y).rounded())
            box.translate(dx: dx, dy: dy)
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
        if let drag = referenceDrag {
            referenceDrag = nil
            if drag.before != storage { registerUndo(DocumentSnapshot(sprite: drag.before, selection: selection)) }
            changed()
        }
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

    /// Aseprite's pixel ratio (Sprite Properties): how wide and tall each pixel shows.
    func setPixelRatio(_ ratio: PixelRatio) {
        guard ratio != storage.pixelRatio else { return }
        performCanvasChange { $0.pixelRatio = ratio }
    }

    /// Grows or shrinks the canvas away from the anchor, in one undo step.
    func resizeCanvas(width: Int, height: Int, anchor: (x: Int, y: Int)) {
        let dx = (width - storage.width) * anchor.x / 2, dy = (height - storage.height) * anchor.y / 2
        resizeCanvas(to: PixelRect(minX: -dx, minY: -dy, maxX: width - 1 - dx, maxY: height - 1 - dy))
    }

    /// The canvas becomes `rect` (current coordinates, reaching past the edges
    /// to grow), in one undo step. Symmetry axes move with the drawing.
    func resizeCanvas(to rect: PixelRect) {
        let w = rect.maxX - rect.minX + 1, h = rect.maxY - rect.minY + 1
        guard w >= 1, h >= 1, w <= Self.maxCanvasSize, h <= Self.maxCanvasSize,
              rect != PixelRect.full(width: storage.width, height: storage.height) else { return }
        var moved = (dx: 0, dy: 0)
        let tiled = tiledMode
        performCanvasChange { moved = $0.resizeCanvas(to: rect, tiled: tiled) }
        if let x2 = symmetry.axisX2 { symmetry.axisX2 = x2 + 2 * moved.dx }
        if let y2 = symmetry.axisY2 { symmetry.axisY2 = y2 + 2 * moved.dy }
    }

    /// Tiled mode > Make the repetition permanent: the canvas becomes `copies`
    /// of itself along the tiled axes, in one undo step, and tiled mode goes off.
    func repeatCanvas(copies: Int) {
        let x = tiledMode.wrapsX ? copies : 1, y = tiledMode.wrapsY ? copies : 1
        guard x > 1 || y > 1, storage.width * x <= Self.maxCanvasSize, storage.height * y <= Self.maxCanvasSize else {
            notice = L10n.string("That would be bigger than %d × %d px", Self.maxCanvasSize, Self.maxCanvasSize)
            return
        }
        performCanvasChange { $0.repeatCanvas(x: x, y: y) }
        tiledMode = .none
    }

    // MARK: Canvas size, on the canvas

    /// Edit > Canvas > Canvas size: the canvas shows its edges with handles;
    /// dragging one moves that side out or in. Nothing changes until Apply.
    func beginCanvasResize() {
        applyTransformIfNeeded()
        stopPlayback()
        deselect()
        canvasResize = .full(width: storage.width, height: storage.height)
        onOverlayChange?()
    }

    /// Drags the `edges` of the proposed canvas from where they were when the
    /// drag started (`from`) by the pointer's travel. With "in cells", sides
    /// land on grid lines.
    func dragCanvasEdges(_ edges: CanvasEdges, from start: PixelRect, by delta: (dx: Double, dy: Double)) {
        var r = start
        func snapX(_ x: Int) -> Int { canvasResizeInCells ? storage.grid.offsetX + Int((Double(x - storage.grid.offsetX) / Double(storage.grid.width)).rounded()) * storage.grid.width : x }
        func snapY(_ y: Int) -> Int { canvasResizeInCells ? storage.grid.offsetY + Int((Double(y - storage.grid.offsetY) / Double(storage.grid.height)).rounded()) * storage.grid.height : y }
        let dx = Int(delta.dx.rounded()), dy = Int(delta.dy.rounded())
        // Sides as grid lines: minX is a line, maxX + 1 is a line.
        if edges.contains(.left) { r.minX = min(start.maxX, snapX(start.minX + dx)) }
        if edges.contains(.right) { r.maxX = max(r.minX, snapX(start.maxX + 1 + dx) - 1) }
        if edges.contains(.top) { r.minY = min(start.maxY, snapY(start.minY + dy)) }
        if edges.contains(.bottom) { r.maxY = max(r.minY, snapY(start.maxY + 1 + dy) - 1) }
        let limit = Self.maxCanvasSize
        if r.maxX - r.minX + 1 > limit { if edges.contains(.left) { r.minX = r.maxX - limit + 1 } else { r.maxX = r.minX + limit - 1 } }
        if r.maxY - r.minY + 1 > limit { if edges.contains(.top) { r.minY = r.maxY - limit + 1 } else { r.maxY = r.minY + limit - 1 } }
        guard r != canvasResize else { return }
        canvasResize = r
        onOverlayChange?()
    }

    func applyCanvasResize() {
        guard let rect = canvasResize else { return }
        canvasResize = nil
        resizeCanvas(to: rect)
        onOverlayChange?()
    }

    func cancelCanvasResize() {
        canvasResize = nil
        onOverlayChange?()
    }
    static let maxCanvasSize = 1024

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

/// Where Arrange puts the selected element among the layers.
enum LayerArrangement {
    case front, forward, backward, back
}

/// A block of cels selected in the timeline: some layers × a run of frames.
/// Like Aseprite, it remembers whether whole frames or whole layers were picked.
struct TimelineRange: Equatable {
    enum Kind { case cels, frames, layers }
    var kind = Kind.cels
    var layers: Set<UUID>
    var frames: ClosedRange<Int>
}

extension SpriteDocument {
    /// Tap on a cel while selecting: the first tap anchors, the next ones grow
    /// the block until it takes in the tapped cel, so cels picked one by one
    /// across layers all end up selected. A tap inside the block trims it back
    /// to the block from the anchor to that cel.
    func extendRange(layer: UUID, frameIndex: Int) {
        guard let anchor = rangeAnchor, let range = timelineRange else {
            rangeAnchor = (layer, frameIndex)
            timelineRange = TimelineRange(layers: [layer], frames: frameIndex...frameIndex)
            return
        }
        let ids = sprite.layers.map(\.id)
        guard let a = ids.firstIndex(of: anchor.layer), let b = ids.firstIndex(of: layer) else { return }
        var rows = min(a, b)...max(a, b)
        var frames = min(anchor.frame, frameIndex)...max(anchor.frame, frameIndex)
        let inside = range.kind == .cels && range.layers.contains(layer) && range.frames.contains(frameIndex)
        if !inside, range.kind == .cels {
            let held = range.layers.compactMap { ids.firstIndex(of: $0) }
            rows = min(rows.lowerBound, held.min() ?? a)...max(rows.upperBound, held.max() ?? a)
            frames = min(frames.lowerBound, range.frames.lowerBound)...max(frames.upperBound, range.frames.upperBound)
        }
        timelineRange = TimelineRange(kind: .cels, layers: Set(ids[rows]), frames: frames)
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

    /// The layers checked in the timeline: those of a layer selection.
    var checkedLayers: Set<UUID> {
        guard let range = timelineRange, range.kind == .layers else { return [] }
        return range.layers
    }

    /// A layer's check box (as in Pixquare): adds the layer to the layer
    /// selection, or takes it out, starting the selection if there's none.
    /// Unchecking the last one ends it.
    func toggleLayerCheck(_ layer: UUID) {
        var layers = checkedLayers
        if layers.contains(layer) { layers.remove(layer) } else { layers.insert(layer) }
        guard !layers.isEmpty else { endRangeSelection(); return }
        isSelectingRange = true
        rangeAnchor = (layer, activeFrameIndex)
        timelineRange = TimelineRange(kind: .layers, layers: layers, frames: 0...(sprite.frames.count - 1))
    }

    /// The header's check box: every layer, or none when they're all checked.
    func toggleAllLayerChecks() {
        let all = Set(sprite.layers.map(\.id))
        guard checkedLayers != all else { endRangeSelection(); return }
        isSelectingRange = true
        rangeAnchor = (sprite.layers.last!.id, activeFrameIndex)
        timelineRange = TimelineRange(kind: .layers, layers: all, frames: 0...(sprite.frames.count - 1))
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

    /// Drags one cel by its dot to another frame or layer, as in Aseprite: it
    /// replaces what's there, and dropping it past the last frame adds frames.
    func moveCel(from: (layer: UUID, frame: Int), to: (layer: UUID, frame: Int)) {
        let ids = sprite.layers.map(\.id)
        guard let a = ids.firstIndex(of: from.layer), let b = ids.firstIndex(of: to.layer),
              (a, from.frame) != (b, to.frame) else { return }
        if timelineRange != nil { endRangeSelection() }
        var applied = (dLayers: 0, dFrames: 0)
        perform { applied = $0.moveCels(layerIndices: [a], frameRange: from.frame...from.frame, dLayers: b - a, dFrames: to.frame - from.frame, copy: false) }
        guard applied != (0, 0) else { return }
        selectCel(layer: sprite.layers[a + applied.dLayers].id, frameIndex: from.frame + applied.dFrames)
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
        // A group is copied with everything in it, the copies inside the new group.
        let ids = Set([id] + sprite.descendants(of: id).map(\.id))
        var placed: [UUID] = []
        perform { s in
            let originals = s.layers.filter { ids.contains($0.id) }.map(\.id)
            placed = s.moveLayers(ids, to: index, copy: true)
            let renamed = Dictionary(uniqueKeysWithValues: zip(originals, placed))
            for i in s.layers.indices where placed.contains(s.layers[i].id) {
                if let p = s.layers[i].parent, let copy = renamed[p] { s.layers[i].parent = copy }
            }
        }
        if let copy = placed.last { activeLayerID = copy }
    }

    /// Adds a reference layer with the image in `data` (PNG, JPEG, HEIC…),
    /// fitted inside the canvas, just under the active layer and half transparent.
    @discardableResult
    func addReferenceLayer(imageData data: Data, name: String? = nil) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width > 0, image.height > 0 else {
            notice = L10n.string("That image can't be opened")
            return false
        }
        let stored = Self.referenceData(for: image) ?? data
        let reference = ReferenceImage(data: stored, frame: Self.fit(CGSize(width: image.width, height: image.height), in: storage, fill: false))
        let layer = Layer(name: name ?? L10n.string("Reference"), opacity: 0.5, reference: reference)
        let index = storage.layers.firstIndex { $0.id == activeLayerID } ?? 0
        perform { s in
            let at = s.layers[index].isBackground ? index + 1 : index
            s.layers.insert(layer, at: at)
        }
        activeLayerID = layer.id
        return true
    }

    /// Fits (or, with `fill`, covers) the canvas with the reference image, centred.
    func fitReference(_ id: UUID, fill: Bool) {
        guard let layer = sprite.layers.first(where: { $0.id == id }), let reference = layer.reference,
              let size = Self.imageSize(of: reference.data) else { return }
        let frame = Self.fit(size, in: storage, fill: fill)
        perform { s in
            if let i = s.layers.firstIndex(where: { $0.id == id }) { s.layers[i].reference?.frame = frame }
        }
    }

    /// Scales the reference image around its centre; `percent` of its fitted size.
    func scaleReference(_ id: UUID, by factor: Double) {
        guard factor > 0 else { return }
        perform { s in
            guard let i = s.layers.firstIndex(where: { $0.id == id }), let f = s.layers[i].reference?.frame else { return }
            let w = f.width * factor, h = f.height * factor
            s.layers[i].reference?.frame = CGRect(x: f.midX - w / 2, y: f.midY - h / 2, width: w, height: h)
        }
    }

    /// Reference images are saved inside the sprite file, so a camera photo is
    /// scaled down to at most 2048 px and kept as JPEG unless it has transparency.
    private static func referenceData(for image: CGImage) -> Data? {
        let longest = max(image.width, image.height)
        var ui = UIImage(cgImage: image)
        if longest > 2048 {
            let scale = 2048 / Double(longest)
            let size = CGSize(width: (Double(image.width) * scale).rounded(), height: (Double(image.height) * scale).rounded())
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            ui = UIGraphicsImageRenderer(size: size, format: format).image { _ in ui.draw(in: CGRect(origin: .zero, size: size)) }
        }
        let alpha = image.alphaInfo
        let opaque = alpha == .none || alpha == .noneSkipLast || alpha == .noneSkipFirst
        return opaque ? ui.jpegData(compressionQuality: 0.85) : ui.pngData()
    }

    private static func imageSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    private static func fit(_ size: CGSize, in sprite: Sprite, fill: Bool) -> CGRect {
        let w = Double(sprite.width), h = Double(sprite.height)
        let scale = fill ? max(w / size.width, h / size.height) : min(w / size.width, h / size.height)
        let fw = size.width * scale, fh = size.height * scale
        return CGRect(x: (w - fw) / 2, y: (h - fh) / 2, width: fw, height: fh)
    }

    // MARK: Tilemaps

    /// Layer > New > New Tilemap Layer, with the sprite grid's cell size as the tile size.
    func addTilemapLayer() {
        let names = Set(sprite.layers.map(\.name))
        var n = sprite.layers.filter(\.isTilemap).count + 1
        while names.contains(L10n.string("Tilemap %d", n)) { n += 1 }
        var layer = Layer(name: L10n.string("Tilemap %d", n))
        layer.tileset = Tileset(tileWidth: max(1, storage.grid.width), tileHeight: max(1, storage.grid.height))
        let index = sprite.layers.firstIndex { $0.id == activeLayerID } ?? sprite.layers.count - 1
        layer.parent = sprite.layers.indices.contains(index) ? sprite.layers[index].parent : nil
        perform { $0.layers.insert(layer, at: index + 1) }
        activeLayerID = layer.id
        selectedTile = 1
    }

    /// Layer > Convert To > Tilemap: its pixels are cut into grid-sized tiles,
    /// identical ones shared.
    func convertToTilemap(_ id: UUID) {
        guard let index = sprite.layers.firstIndex(where: { $0.id == id }) else { return }
        let layer = sprite.layers[index]
        guard !layer.isTilemap, !layer.isGroup, !layer.isReference, !layer.isBackground else { return }
        let tileset = Tileset(tileWidth: max(1, storage.grid.width), tileHeight: max(1, storage.grid.height))
        perform { s in
            s.layers[index].tileset = tileset
            s.layers[index].isContinuous = false
            s.syncTilemaps(mode: .auto)
        }
    }

    /// Layer > Convert To > Layer: keeps the pixels, forgets the tiles.
    func convertToNormalLayer(_ id: UUID) {
        updateLayer(id) { $0.tileset = nil }
    }

    /// The cell under `p` on the active tilemap.
    private func tileCell(at p: PixelPoint) -> (column: Int, row: Int, tileset: Tileset)? {
        guard let tileset = activeLayer?.tileset, p.x >= 0, p.y >= 0, p.x < storage.width, p.y < storage.height else { return nil }
        return (p.x / tileset.tileWidth, p.y / tileset.tileHeight, tileset)
    }

    /// Tiles mode: the pencil places the selected tile, the eraser the empty one.
    private func placeTile(at p: PixelPoint) {
        guard let (column, row, tileset) = tileCell(at: p) else { return }
        let index = tool == .eraser ? 0 : min(max(0, selectedTile), tileset.tiles.count - 1)
        setTiles([(column, row)], to: index, tileset: tileset)
    }

    /// Tiles mode bucket: the connected cells showing the same tile take the selected one.
    private func fillTiles(at p: PixelPoint) {
        guard let (column, row, tileset) = tileCell(at: p) else { return }
        let map = storage.tilemaps[activeCelKey]
            ?? TileMap(columns: tileset.columns(width: storage.width), rows: tileset.rows(height: storage.height))
        let target = map[column, row]
        let index = min(max(0, selectedTile), tileset.tiles.count - 1)
        guard target != index else { return }
        var seen: Set<Int> = [], cells: [(Int, Int)] = [], stack = [(column, row)]
        while let (c, r) = stack.popLast() {
            guard c >= 0, r >= 0, c < map.columns, r < map.rows, !seen.contains(r * map.columns + c), map[c, r] == target else { continue }
            seen.insert(r * map.columns + c)
            cells.append((c, r))
            stack += [(c + 1, r), (c - 1, r), (c, r + 1), (c, r - 1)]
        }
        setTiles(cells, to: index, tileset: tileset)
    }

    private func setTiles(_ cells: [(Int, Int)], to index: Int, tileset: Tileset) {
        let key = activeCelKey
        var map = storage.tilemaps[key]
            ?? TileMap(columns: tileset.columns(width: storage.width), rows: tileset.rows(height: storage.height))
        let changedCells = cells.filter { map[$0.0, $0.1] != index }
        guard !changedCells.isEmpty else { return }
        for (c, r) in changedCells { map[c, r] = index }
        storage.tilemaps[key] = map
        let rects = changedCells.map { PixelRect(minX: $0.0 * tileset.tileWidth, minY: $0.1 * tileset.tileHeight,
                                                 maxX: ($0.0 + 1) * tileset.tileWidth - 1, maxY: ($0.1 + 1) * tileset.tileHeight - 1) }
        let dirty = rects.dropFirst().reduce(rects[0]) { $0.union($1) }.clipped(width: storage.width, height: storage.height)
        mutateActiveCel(dirty: dirty) { image in
            for (c, r) in changedCells { Sprite.draw(tileset.tiles[index], into: &image, column: c, row: r) }
        }
    }

    /// Tiles mode eyedropper: picks the tile under the finger.
    private func pickTile(at p: PixelPoint) {
        guard let (column, row, _) = tileCell(at: p), let map = sprite.tilemaps[activeCelKey] else { return }
        selectedTile = map[column, row]
    }

    /// Layer > Merge Down: the layer is drawn onto the one below it, frame by
    /// frame, with its opacity, and disappears.
    func mergeDown(_ id: UUID) {
        guard let index = sprite.layers.firstIndex(where: { $0.id == id }), index > 0,
              !sprite.layers[index].isReference, !sprite.layers[index - 1].isReference,
              !sprite.layers[index].isGroup, !sprite.layers[index - 1].isGroup,
              sprite.layers[index].parent == sprite.layers[index - 1].parent else { return }
        let lower = sprite.layers[index - 1].id
        perform { s in s.mergeDown(at: index) }
        activeLayerID = lower
    }

    /// Layer > Flatten: every visible layer becomes one (the background if
    /// there was one). Hidden layers are dropped, as in Aseprite.
    func flatten() {
        guard sprite.layers.count > 1 else { return }
        var flat: UUID?
        perform { s in flat = s.flatten(name: L10n.string("Flattened")) }
        if let flat { activeLayerID = flat }
    }

    /// Aseprite's Ctrl+J / Ctrl+Shift+J: the selected pixels of the active cel
    /// go to a new layer above it, copied or cut.
    func newLayerFromSelection(cut: Bool) {
        guard let mask = selection, let source = storage.cels[activeCelKey],
              let index = storage.layers.firstIndex(where: { $0.id == activeLayerID }) else { return }
        if cut, !activeLayerEditable { return }
        let layer = Layer(name: newLayerName())
        let frame = activeFrame.id, active = activeCelKey, erase = eraseColor
        perform { s in
            var image = PixelImage(width: s.width, height: s.height)
            for i in mask.bits.indices where mask.bits[i] { image.pixels[i] = source.pixels[i] }
            s.layers.insert(layer, at: index + 1)
            if !image.isEmpty { s.cels[CelKey(layer: layer.id, frame: frame)] = image }
            if cut, var cel = s.cels[active] {
                for i in mask.bits.indices where mask.bits[i] { cel.pixels[i] = erase }
                s.cels[active] = cel.isEmpty ? nil : cel
                s.syncLinks(from: active)
            }
        }
        activeLayerID = layer.id
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
    let tiling: TiledMode
    var coverage: [UInt8]
    /// Paint again at the same strength instead of skipping pixels already painted.
    var repaints = false

    /// `color` overrides the painter's color for this pixel (gradients).
    mutating func paint(_ point: PixelPoint, alpha: UInt8, color: PixelColor? = nil, on image: inout PixelImage) {
        let q = tiling == .none ? point : tiling.wrap(point, width: image.width, height: image.height)
        guard image.contains(q), mask?.contains(q) ?? true else { return }
        let i = q.y * image.width + q.x
        guard alpha > coverage[i] || (repaints && alpha == coverage[i]) else { return }
        coverage[i] = alpha
        let ramp = ramp, direction = direction
        image.pixels[i] = ink.apply(color ?? self.color, over: original?.pixels[i] ?? .clear, alpha: alpha) { direction.step($0, in: ramp) }
    }
}

/// Which edges of a slice follow a drag.
struct SliceEdges: OptionSet {
    let rawValue: Int
    static let left = SliceEdges(rawValue: 1), right = SliceEdges(rawValue: 2)
    static let top = SliceEdges(rawValue: 4), bottom = SliceEdges(rawValue: 8)
    /// Moving: the whole slice.
    static let all: SliceEdges = [.left, .right, .top, .bottom]
    /// A new slice drawn from the touch-down point.
    static let drawing = SliceEdges(rawValue: 16)

    /// The edges a touch at `p` grabs: on (or just outside) an edge resizes
    /// it, a corner both; inside moves the slice. Tiny slices only move.
    init(_ p: PixelPoint, _ b: PixelRect) {
        var e: SliceEdges = []
        if b.width > 2 { if p.x <= b.minX { e.insert(.left) } else if p.x >= b.maxX { e.insert(.right) } }
        if b.height > 2 { if p.y <= b.minY { e.insert(.top) } else if p.y >= b.maxY { e.insert(.bottom) } }
        self = e.isEmpty ? .all : e
    }

    init(rawValue: Int) { self.rawValue = rawValue }
}

/// Everything about a sprite except its pixels, to tell structural changes
/// apart from drawing.
private struct StructureKey: Equatable {
    let width: Int, height: Int
    let layers: [Layer]
    let frames: [Frame]
    let tags: [FrameTag]
    let palette: [PixelColor]
    let links: [CelKey: UUID]
    let celOpacity: [CelKey: Double]
    let grid: GridSettings
    let slices: [Slice]
    let tilemaps: [CelKey: TileMap]
    /// Which cels have content (empty cels are removed from `cels`).
    let filled: Set<CelKey>

    init(_ s: Sprite) {
        width = s.width; height = s.height
        layers = s.layers; frames = s.frames; tags = s.tags; palette = s.palette
        links = s.links; celOpacity = s.celOpacity; grid = s.grid; slices = s.slices
        tilemaps = s.tilemaps
        filled = Set(s.cels.keys)
    }
}

// MARK: - Scripts
// https://www.aseprite.org/docs/scripting/

extension SpriteDocument {
    /// Runs an Aseprite script on this sprite.
    func runScript(named name: String, source: String) {
        applyTransformIfNeeded()
        let engine = ScriptEngine(name: name, document: self)
        scriptEngines.append(engine)
        engine.start(source: source)
    }

    /// What a script changed, as one undo step (Aseprite's app.transaction), or as part of
    /// the last step when the script answered it (a stroke, for Magic Pencil).
    func applyScript(_ sprite: Sprite, selection: SelectionMask?, activeLayer: UUID, frameIndex: Int, merging: Bool = false) {
        applyingScript = true
        defer { applyingScript = false }
        if sprite != storage {
            if merging && canUndo {
                storage = sprite
                if storage.layers.contains(where: { $0.isGroup || $0.parent != nil }) { storage.normalizeGroups() }
                changed()
            } else {
                perform { $0 = sprite }
            }
        }
        if selection != self.selection {
            // A selection from before the script resized the sprite doesn't fit it any more.
            if let selection, selection.width == storage.width, selection.height == storage.height {
                self.selection = selection
            } else {
                self.selection = nil
            }
        }
        if storage.layers.contains(where: { $0.id == activeLayer && !$0.isGroup }) { activeLayerID = activeLayer }
        activeFrameIndex = min(max(0, frameIndex), storage.frames.count - 1)
    }

    /// Runs an extension's command (`plugin:newCommand`); one of an extension at a time.
    func runCommand(_ command: AsepriteExtension.Command, of package: AsepriteExtension) {
        guard !scriptEngines.contains(where: { $0.name == package.displayName }) else { return }
        applyTransformIfNeeded()
        let engine = ScriptEngine(name: package.displayName, document: self, folder: ExtensionStore.shared.folder(of: package),
                                  preferencesKey: "extension.\(package.id).preferences")
        scriptEngines.append(engine)
        engine.startPlugin(entry: command.script, command: command.id)
    }

    /// Tells running scripts what happened, after the change that caused it.
    fileprivate func notifyScripts(_ event: ScriptEvent) {
        guard !scriptEngines.isEmpty, !applyingScript else { return }
        if case .site = event {
            // Playback moves the frame many times a second: one site event at a time.
            guard !siteEventPending else { return }
            siteEventPending = true
        }
        Task { @MainActor [weak self] in
            guard let self else { return }
            if case .site = event { self.siteEventPending = false }
            for engine in self.scriptEngines { engine.handle(event) }
        }
    }

    func scriptFinished(_ engine: ScriptEngine) {
        scriptEngines.removeAll { $0 === engine }
    }

    /// The editor is closing: scripts stop and their dialogs close.
    func stopScripts() {
        for engine in scriptEngines { engine.stop() }
        scriptDialogs = []
    }
}
