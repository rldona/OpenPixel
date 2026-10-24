import UIKit

/// A neighbouring frame drawn faintly under the current one.
struct OnionLayer {
    let image: CGImage
    let alpha: CGFloat
}

/// The drawing surface. UIKit instead of SwiftUI gestures because we need
/// per-touch control: Apple Pencil vs finger, coalesced touches, and turning
/// a one-finger stroke into a pinch when a second finger lands.
///
/// - Apple Pencil (or a single finger while no Pencil has been used) draws.
/// - Two fingers pinch/pan; two-finger tap undoes, three-finger tap redoes.
/// - Once a Pencil is seen, a long press with a finger is a quick eyedropper.
///
/// Rendering is built from Core Animation layers so the GPU does the scaling:
/// panning and zooming only move layers, and a stroke recomposites just the
/// pixels it touched (`render(_:)`) instead of redrawing the whole view.
final class PixelCanvasView: UIView, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
    weak var document: SpriteDocument?

    var spriteSize = CGSize(width: 32, height: 32) {
        didSet { if oldValue != spriteSize { needsFit = true; setNeedsLayout() } }
    }
    var onionLayers: [OnionLayer] = [] { didSet { updateOnionLayers() } }
    var showGrid = true { didSet { if oldValue != showGrid { updateOverlays() } } }
    var mirrorX = false { didSet { if oldValue != mirrorX { updateOverlays() } } }

    /// Points come with the Apple Pencil's pressure, 0...1 (always 1 for fingers).
    var onStrokeBegan: ((PixelPoint, Double) -> Void)?
    var onStrokeMoved: (([PixelPoint], [Double]) -> Void)?
    var onStrokeEnded: (() -> Void)?
    var onStrokeCancelled: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onEyedropper: ((PixelPoint) -> Void)?
    var onPencilDoubleTap: (() -> Void)?
    var onZoomChanged: ((CGFloat) -> Void)?
    /// Four-finger tap: show or hide the panels around the canvas.
    var onFocusToggle: (() -> Void)?
    /// Transform drags, in sprite coordinates with sub-pixel precision.
    var onTransformBegan: ((TransformHandle, CGPoint) -> Void)?
    var onTransformMoved: ((CGPoint) -> Void)?
    var onTransformEnded: (() -> Void)?
    /// A tap outside the transform box: drop the floating pixels.
    var onTransformOutsideTap: (() -> Void)?

    /// Screen points per sprite pixel.
    private(set) var scale: CGFloat = 1
    /// Top-left corner of the sprite in view coordinates.
    private var origin: CGPoint = .zero
    private var needsFit = true
    private var lastBoundsSize: CGSize = .zero
    private var pencilOnly = false
    private weak var drawingTouch: UITouch?
    private var strokeActive = false
    private weak var transformTouch: UITouch?
    /// A touch inside the selection: it moves the pixels once it drags,
    /// and selects the element under it if it lifts without moving.
    private var pendingSelectionTouch: (touch: UITouch, start: CGPoint, point: PixelPoint)?

    /// What the document looked like the last time the whole image was rendered.
    private(set) var renderedRevision = -1
    private(set) var renderedFrame = -1
    /// The current frame's composite, updated in place while drawing.
    private var buffer: [PixelColor] = []
    private var bufferSize = (width: 0, height: 0)

    private let shadowLayer = CALayer()
    private let spriteLayer = CALayer()
    private let checkerLayer = CALayer()
    private let onionHost = CALayer()
    private let imageLayer = CALayer()
    private let gridLayer = CAShapeLayer()
    private let mirrorLayer = CAShapeLayer()
    /// Marching ants: a white line under black animated dashes, visible on any color.
    private let antsBack = CAShapeLayer()
    private let antsFront = CAShapeLayer()
    private let boxLayer = CAShapeLayer()
    private let handlesLayer = CAShapeLayer()
    /// Control points of a curve, corners of a polygon being built.
    private let guidesLayer = CAShapeLayer()
    /// Selection edges in sprite coordinates, recomputed when the selection changes.
    private var outline: [(PixelPoint, PixelPoint)] = []
    /// Cell size and grid of the current checker image; it's rebuilt when any changes.
    private var checkerKey: [Int] = []

    private static let minScale: CGFloat = 1
    private static let maxScale: CGFloat = 128
    /// Room kept free at the top for the floating tool options bar.
    private static let topInset: CGFloat = 72
    private static let bottomInset: CGFloat = 72
    private var isDark: Bool { traitCollection.userInterfaceStyle == .dark }
    private var checkerLight: PixelColor { isDark ? PixelColor(r: 69, g: 69, b: 69) : PixelColor(r: 236, g: 236, b: 236) }
    private var checkerDark: PixelColor { isDark ? PixelColor(r: 54, g: 54, b: 54) : PixelColor(r: 212, g: 212, b: 212) }
    /// Layer properties we change every frame must not animate.
    private static let noAnimations: [String: CAAction] = [
        "contents": NSNull(), "position": NSNull(), "bounds": NSNull(), "frame": NSNull(),
        "path": NSNull(), "hidden": NSNull(), "opacity": NSNull(), "shadowPath": NSNull(), "sublayers": NSNull()
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(Theme.background)
        // The sprite layers move freely when zooming and panning; keep them
        // from drawing over the toolbars around the canvas.
        clipsToBounds = true
        isMultipleTouchEnabled = true
        setUpLayers()
        setUpGestures()
        applyAppearance()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: PixelCanvasView, _) in
            view.applyAppearance()
        }
    }

    /// Layer colors are CGColors, which don't follow light/dark by themselves.
    private func applyAppearance() {
        let traits = traitCollection
        spriteLayer.borderColor = UIColor(Theme.border).resolvedColor(with: traits).cgColor
        gridLayer.strokeColor = (isDark ? UIColor(white: 1, alpha: 0.22) : UIColor(white: 0, alpha: 0.18)).cgColor
        mirrorLayer.strokeColor = UIColor(Theme.accent).resolvedColor(with: traits).cgColor
        boxLayer.strokeColor = UIColor(Theme.accent).resolvedColor(with: traits).cgColor
        handlesLayer.strokeColor = UIColor(Theme.accent).resolvedColor(with: traits).cgColor
        guidesLayer.strokeColor = UIColor(Theme.accent).resolvedColor(with: traits).cgColor
        shadowLayer.shadowOpacity = isDark ? 0.5 : 0.15
        checkerLayer.contents = nil
        updateChecker()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func setUpLayers() {
        for l in [shadowLayer, spriteLayer, checkerLayer, onionHost, imageLayer, gridLayer, mirrorLayer] {
            l.actions = Self.noAnimations
        }
        shadowLayer.shadowColor = UIColor.black.cgColor
        shadowLayer.shadowOpacity = 0.5
        shadowLayer.shadowRadius = 16
        shadowLayer.shadowOffset = CGSize(width: 0, height: 12)

        spriteLayer.masksToBounds = true
        spriteLayer.borderWidth = 1
        for l in [checkerLayer, imageLayer] {
            l.magnificationFilter = .nearest
            l.minificationFilter = .nearest
        }
        spriteLayer.addSublayer(checkerLayer)
        spriteLayer.addSublayer(onionHost)
        spriteLayer.addSublayer(imageLayer)

        gridLayer.fillColor = nil
        mirrorLayer.fillColor = nil
        mirrorLayer.lineWidth = 2
        mirrorLayer.lineDashPattern = [6, 5]

        layer.addSublayer(shadowLayer)
        layer.addSublayer(spriteLayer)
        layer.addSublayer(gridLayer)
        layer.addSublayer(mirrorLayer)

        for l in [antsBack, antsFront, boxLayer, handlesLayer, guidesLayer] {
            l.actions = Self.noAnimations
            l.fillColor = nil
            layer.addSublayer(l)
        }
        antsBack.strokeColor = UIColor.white.cgColor
        antsBack.lineWidth = 1
        antsFront.strokeColor = UIColor.black.cgColor
        antsFront.lineWidth = 1
        antsFront.lineDashPattern = [4, 4]
        let march = CABasicAnimation(keyPath: "lineDashPhase")
        march.fromValue = 0
        march.toValue = 8
        march.duration = 0.6
        march.repeatCount = .infinity
        antsFront.add(march, forKey: "march")
        boxLayer.lineWidth = 1.5
        handlesLayer.fillColor = UIColor.white.cgColor
        handlesLayer.lineWidth = 1.5
        guidesLayer.fillColor = UIColor.white.cgColor
        guidesLayer.lineWidth = 1.5
    }

    private func setUpGestures() {
        let fingers = [NSNumber(value: UITouch.TouchType.direct.rawValue)]

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.allowedTouchTypes = fingers
        pinch.delegate = self
        addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.allowedTouchTypes = fingers
        pan.delegate = self
        addGestureRecognizer(pan)

        // Trackpad / mouse scrolling pans the canvas.
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scroll.allowedScrollTypesMask = .continuous
        scroll.allowedTouchTypes = []
        addGestureRecognizer(scroll)

        let undoTap = UITapGestureRecognizer(target: self, action: #selector(handleUndoTap(_:)))
        undoTap.numberOfTouchesRequired = 2
        undoTap.allowedTouchTypes = fingers
        addGestureRecognizer(undoTap)

        let redoTap = UITapGestureRecognizer(target: self, action: #selector(handleRedoTap(_:)))
        redoTap.numberOfTouchesRequired = 3
        redoTap.allowedTouchTypes = fingers
        addGestureRecognizer(redoTap)

        let focusTap = UITapGestureRecognizer(target: self, action: #selector(handleFocusTap(_:)))
        focusTap.numberOfTouchesRequired = 4
        focusTap.allowedTouchTypes = fingers
        addGestureRecognizer(focusTap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        longPress.allowedTouchTypes = fingers
        longPress.delegate = self
        addGestureRecognizer(longPress)

        let pencil = UIPencilInteraction()
        pencil.delegate = self
        addInteraction(pencil)
    }

    // MARK: - Rendering

    /// Recomposites the whole current frame, e.g. after undo or a frame change.
    func renderAll() {
        guard let document else { return }
        let sprite = document.sprite
        if bufferSize != (sprite.width, sprite.height) {
            buffer = [PixelColor](repeating: .clear, count: sprite.width * sprite.height)
            bufferSize = (sprite.width, sprite.height)
        }
        sprite.composite(frameIndex: document.activeFrameIndex, into: &buffer, rect: .full(width: sprite.width, height: sprite.height))
        renderedRevision = document.revision
        renderedFrame = document.activeFrameIndex
        pushImage()
        selectionChanged()
    }

    /// Recomposites only `rect` while a stroke is in progress.
    func render(_ rect: PixelRect) {
        guard let document else { return }
        let sprite = document.sprite
        guard bufferSize == (sprite.width, sprite.height) else { return renderAll() }
        sprite.composite(frameIndex: document.activeFrameIndex, into: &buffer, rect: rect)
        pushImage()
    }

    private func pushImage() {
        imageLayer.contents = PixelImage.makeCGImage(pixels: buffer, width: bufferSize.width, height: bufferSize.height)
    }

    private func updateOnionLayers() {
        onionHost.sublayers = onionLayers.map { onion in
            let l = CALayer()
            l.actions = Self.noAnimations
            l.contents = onion.image
            l.opacity = Float(onion.alpha)
            l.magnificationFilter = .nearest
            l.minificationFilter = .nearest
            l.frame = onionHost.bounds
            return l
        }
    }

    /// Checker squares are a whole number of sprite pixels (1, 2, 4…) so they line up
    /// with the pixel grid; at high zoom each square is exactly one pixel.
    private func updateChecker() {
        var pixelsPerCell = 1
        while scale * CGFloat(pixelsPerCell) < 8 { pixelsPerCell *= 2 }
        let columns = Int((spriteSize.width / CGFloat(pixelsPerCell)).rounded(.up))
        let rows = Int((spriteSize.height / CGFloat(pixelsPerCell)).rounded(.up))
        let key = [pixelsPerCell, columns, rows]
        if key != checkerKey || checkerLayer.contents == nil {
            var tile = PixelImage(width: columns, height: rows, fill: checkerLight)
            for y in 0..<rows {
                for x in 0..<columns where (x + y) % 2 == 0 { tile[x, y] = checkerDark }
            }
            checkerLayer.contents = tile.makeCGImage()
            checkerKey = key
        }
        let cell = scale * CGFloat(pixelsPerCell)
        checkerLayer.frame = CGRect(x: 0, y: 0, width: CGFloat(columns) * cell, height: CGFloat(rows) * cell)
    }

    private var spriteRect: CGRect {
        CGRect(origin: origin, size: CGSize(width: spriteSize.width * scale, height: spriteSize.height * scale))
    }

    /// Moves and resizes the layers after a pan, zoom or rotation. Nothing is redrawn.
    private func updateGeometry() {
        let rect = spriteRect
        spriteLayer.frame = rect
        shadowLayer.frame = rect
        shadowLayer.shadowPath = UIBezierPath(rect: CGRect(origin: .zero, size: rect.size)).cgPath
        imageLayer.frame = spriteLayer.bounds
        onionHost.frame = spriteLayer.bounds
        onionHost.sublayers?.forEach { $0.frame = onionHost.bounds }
        updateChecker()
        updateOverlays()
    }

    /// The selection or the transform box changed.
    func selectionChanged() {
        outline = document?.selection?.outline() ?? []
        updateSelectionOverlay()
    }

    private func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale)
    }

    private func toSprite(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale)
    }

    /// Where the rotation knob sits: above the middle of the box's top edge.
    private func knobPoint(_ box: TransformBox) -> (anchor: CGPoint, knob: CGPoint) {
        let topMid = toView(box.handles[1])
        let center = toView(box.toWorld(box.center))
        var dx = topMid.x - center.x, dy = topMid.y - center.y
        let length = max(0.001, (dx * dx + dy * dy).squareRoot())
        if length < 0.01 { dx = 0; dy = -1 } else { dx /= length; dy /= length }
        return (topMid, CGPoint(x: topMid.x + dx * 32, y: topMid.y + dy * 32))
    }

    private func updateSelectionOverlay() {
        let ants = CGMutablePath()
        for (a, b) in outline {
            ants.move(to: toView(CGPoint(x: a.x, y: a.y)))
            ants.addLine(to: toView(CGPoint(x: b.x, y: b.y)))
        }
        antsBack.frame = bounds
        antsFront.frame = bounds
        antsBack.path = ants
        antsFront.path = ants

        updateGuides()
        boxLayer.frame = bounds
        handlesLayer.frame = bounds
        guard let box = document?.isTransforming == true ? document?.transformBox : nil else {
            boxLayer.path = nil
            handlesLayer.path = nil
            return
        }
        let corners = box.corners.map(toView)
        let boxPath = CGMutablePath()
        boxPath.addLines(between: corners + [corners[0]])
        let knob = knobPoint(box)
        boxPath.move(to: knob.anchor)
        boxPath.addLine(to: knob.knob)
        boxLayer.path = boxPath

        let handles = CGMutablePath()
        for p in box.handles.map(toView) {
            handles.addRect(CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
        }
        handles.addEllipse(in: CGRect(x: knob.knob.x - 7, y: knob.knob.y - 7, width: 14, height: 14))
        let pivot = toView(box.pivot)
        handles.addEllipse(in: CGRect(x: pivot.x - 5, y: pivot.y - 5, width: 10, height: 10))
        handlesLayer.path = handles
    }

    private func updateGuides() {
        guidesLayer.frame = bounds
        guard let guides = document?.shapeGuides, !guides.handles.isEmpty else {
            guidesLayer.path = nil
            return
        }
        func center(_ p: PixelPoint) -> CGPoint { toView(CGPoint(x: Double(p.x) + 0.5, y: Double(p.y) + 0.5)) }
        let path = CGMutablePath()
        for (a, b) in guides.lines {
            path.move(to: center(a))
            path.addLine(to: center(b))
        }
        let radius = max(5, min(8, scale / 2))
        for p in guides.handles.map(center) {
            path.addEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
        }
        guidesLayer.path = path
    }

    /// What a touch at `location` (view coordinates) would grab on the transform box.
    private func transformHandle(at location: CGPoint) -> TransformHandle? {
        guard let box = document?.transformBox else { return nil }
        func near(_ p: CGPoint, _ radius: CGFloat) -> Bool {
            let dx = p.x - location.x, dy = p.y - location.y
            return dx * dx + dy * dy <= radius * radius
        }
        if near(toView(box.pivot), 16) { return .pivot }
        if near(knobPoint(box).knob, 24) { return .rotate }
        let handles = box.handles.map(toView)
        for i in [0, 2, 4, 6, 1, 3, 5, 7] where near(handles[i], 22) { return .scale(i) }
        if box.contains(toSprite(location)) { return .move }
        // Just outside a corner rotates, like Aseprite.
        if box.corners.map(toView).contains(where: { near($0, 56) }) { return .rotate }
        return nil
    }

    /// Grid and symmetry lines are drawn in view coordinates, only over the visible part.
    private func updateOverlays() {
        updateSelectionOverlay()
        gridLayer.frame = bounds
        mirrorLayer.frame = bounds
        let rect = spriteRect
        let visible = rect.intersection(bounds)

        if showGrid, scale >= 6, !visible.isNull {
            gridLayer.lineWidth = 1 / max(1, traitCollection.displayScale)
            let path = CGMutablePath()
            let firstX = max(1, Int(((visible.minX - rect.minX) / scale).rounded(.down)))
            let lastX = min(Int(spriteSize.width) - 1, Int(((visible.maxX - rect.minX) / scale).rounded(.up)))
            let firstY = max(1, Int(((visible.minY - rect.minY) / scale).rounded(.down)))
            let lastY = min(Int(spriteSize.height) - 1, Int(((visible.maxY - rect.minY) / scale).rounded(.up)))
            if firstX <= lastX {
                for x in firstX...lastX {
                    let px = rect.minX + CGFloat(x) * scale
                    path.move(to: CGPoint(x: px, y: visible.minY))
                    path.addLine(to: CGPoint(x: px, y: visible.maxY))
                }
            }
            if firstY <= lastY {
                for y in firstY...lastY {
                    let py = rect.minY + CGFloat(y) * scale
                    path.move(to: CGPoint(x: visible.minX, y: py))
                    path.addLine(to: CGPoint(x: visible.maxX, y: py))
                }
            }
            gridLayer.path = path
            gridLayer.isHidden = false
        } else {
            gridLayer.isHidden = true
        }

        if mirrorX {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            mirrorLayer.path = path
            mirrorLayer.isHidden = false
        } else {
            mirrorLayer.isHidden = true
        }
    }

    // MARK: - Viewport

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        if needsFit {
            fitToScreen()
        } else if bounds.size != lastBoundsSize {
            // Keep the sprite where it was relative to the centre, e.g. on rotation.
            origin.x += (bounds.width - lastBoundsSize.width) / 2
            origin.y += (bounds.height - lastBoundsSize.height) / 2
            updateGeometry()
        }
        lastBoundsSize = bounds.size
    }

    func fitToScreen() {
        let margin: CGFloat = 32
        // Leave room below for the floating selection and transform bars.
        let available = CGSize(width: bounds.width - margin * 2, height: bounds.height - Self.topInset - Self.bottomInset)
        let fit = min(available.width / spriteSize.width, available.height / spriteSize.height)
        scale = max(Self.minScale, min(Self.maxScale, fit >= 1 ? fit.rounded(.down) : fit))
        origin = CGPoint(
            x: ((bounds.width - spriteSize.width * scale) / 2).rounded(),
            y: (Self.topInset + (available.height - spriteSize.height * scale) / 2).rounded()
        )
        needsFit = false
        onZoomChanged?(scale)
        updateGeometry()
    }

    func zoom(by factor: CGFloat) {
        setScale((scale * factor).rounded(), anchor: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    private func setScale(_ newScale: CGFloat, anchor: CGPoint) {
        let clamped = min(Self.maxScale, max(Self.minScale, newScale))
        let sx = (anchor.x - origin.x) / scale
        let sy = (anchor.y - origin.y) / scale
        scale = clamped
        origin = CGPoint(x: anchor.x - sx * scale, y: anchor.y - sy * scale)
        onZoomChanged?(scale)
        updateGeometry()
    }

    private func spritePoint(_ location: CGPoint) -> PixelPoint? {
        let x = Int(((location.x - origin.x) / scale).rounded(.down))
        let y = Int(((location.y - origin.y) / scale).rounded(.down))
        guard x >= 0, y >= 0, x < Int(spriteSize.width), y < Int(spriteSize.height) else { return nil }
        return PixelPoint(x: x, y: y)
    }

    // MARK: - Gestures

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            cancelActiveStroke()
        case .changed:
            setScale(scale * g.scale, anchor: g.location(in: self))
            g.scale = 1
        case .ended, .cancelled:
            // Snap to whole zoom levels so every sprite pixel has the same size.
            if scale >= 1 { setScale(scale.rounded(), anchor: g.location(in: self)) }
        default:
            break
        }
    }

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        if g.state == .began { cancelActiveStroke() }
        guard g.state == .changed else { return }
        translate(by: g.translation(in: self))
        g.setTranslation(.zero, in: self)
    }

    @objc private func handleScroll(_ g: UIPanGestureRecognizer) {
        guard g.state == .changed else { return }
        translate(by: g.translation(in: self))
        g.setTranslation(.zero, in: self)
    }

    private func translate(by t: CGPoint) {
        origin.x += t.x
        origin.y += t.y
        updateGeometry()
    }

    @objc private func handleUndoTap(_ g: UITapGestureRecognizer) {
        cancelActiveStroke()
        onUndo?()
    }

    @objc private func handleFocusTap(_ g: UITapGestureRecognizer) {
        cancelActiveStroke()
        onFocusToggle?()
    }

    @objc private func handleRedoTap(_ g: UITapGestureRecognizer) {
        cancelActiveStroke()
        onRedo?()
    }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began || g.state == .changed, let p = spritePoint(g.location(in: self)) else { return }
        onEyedropper?(p)
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        (g is UIPinchGestureRecognizer && other is UIPanGestureRecognizer)
            || (g is UIPanGestureRecognizer && other is UIPinchGestureRecognizer)
    }

    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if g is UILongPressGestureRecognizer { return pencilOnly }
        return true
    }

    // MARK: - Apple Pencil double tap

    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        handlePencilTap()
    }

    @available(iOS 17.5, *)
    func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) {
        handlePencilTap()
    }

    private func handlePencilTap() {
        guard UIPencilInteraction.preferredTapAction != .ignore else { return }
        onPencilDoubleTap?()
    }

    // MARK: - Drawing touches

    private func pressure(of touch: UITouch) -> Double {
        guard touch.type == .pencil, touch.maximumPossibleForce > 0 else { return 1 }
        return min(1, max(0.05, Double(touch.force / touch.maximumPossibleForce)))
    }

    private func canDraw(with touch: UITouch) -> Bool {
        switch touch.type {
        case .pencil, .indirectPointer: true
        case .direct: !pencilOnly
        default: false
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if transformTouch != nil { return }
        if let document, document.isTransforming || document.tool == .move,
           let touch = touches.first(where: canDraw), drawingTouch == nil {
            if touch.type == .pencil { pencilOnly = true }
            if touch.type == .direct, (event?.allTouches?.filter { $0.type == .direct }.count ?? 1) > 1 { return }
            let location = touch.location(in: self)
            if let handle = transformHandle(at: location) {
                transformTouch = touch
                onTransformBegan?(handle, toSprite(location))
            } else if document.isTransforming {
                onTransformOutsideTap?()
            } else {
                transformTouch = touch
                onTransformBegan?(.move, toSprite(location))
            }
            return
        }
        // Dragging inside the selection with a selection tool moves its pixels.
        if let document, drawingTouch == nil, let touch = touches.first(where: canDraw),
           let p = spritePoint(touch.location(in: self)), document.dragMovesSelection(at: p) {
            if touch.type == .pencil { pencilOnly = true }
            if touch.type == .direct, (event?.allTouches?.filter { $0.type == .direct }.count ?? 1) > 1 { return }
            pendingSelectionTouch = (touch, touch.location(in: self), p)
            return
        }
        if drawingTouch != nil {
            // A second finger joined a finger stroke: it's a gesture, not a drawing.
            if drawingTouch?.type == .direct, touches.contains(where: { $0.type == .direct }) {
                cancelActiveStroke()
            }
            return
        }
        guard let touch = touches.first(where: canDraw) else { return }
        if touch.type == .pencil { pencilOnly = true }
        if touch.type == .direct, (event?.allTouches?.filter { $0.type == .direct }.count ?? 1) > 1 { return }
        drawingTouch = touch
        if let p = spritePoint(touch.location(in: self)) {
            strokeActive = true
            onStrokeBegan?(p, pressure(of: touch))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let pending = pendingSelectionTouch, touches.contains(pending.touch) {
            let now = pending.touch.location(in: self)
            guard hypot(now.x - pending.start.x, now.y - pending.start.y) > 6 else { return }
            pendingSelectionTouch = nil
            transformTouch = pending.touch
            onTransformBegan?(.move, toSprite(pending.start))
            onTransformMoved?(toSprite(now))
            return
        }
        if let touch = transformTouch, touches.contains(touch) {
            onTransformMoved?(toSprite(touch.location(in: self)))
            return
        }
        guard let touch = drawingTouch, touches.contains(touch) else { return }
        // The Pencil reports up to 240 samples per second; handle all of an
        // event's samples in one batch so the canvas updates once per event.
        var points: [PixelPoint] = []
        var pressures: [Double] = []
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            guard let p = spritePoint(sample.location(in: self)) else { continue }
            if !strokeActive {
                strokeActive = true
                onStrokeBegan?(p, pressure(of: sample))
            } else if points.last != p {
                points.append(p)
                pressures.append(pressure(of: sample))
            } else {
                pressures[pressures.count - 1] = max(pressures[pressures.count - 1], pressure(of: sample))
            }
        }
        if !points.isEmpty { onStrokeMoved?(points, pressures) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let pending = pendingSelectionTouch, touches.contains(pending.touch) {
            // A tap inside the selection: select the element under it.
            pendingSelectionTouch = nil
            onStrokeBegan?(pending.point, 1)
            onStrokeEnded?()
            return
        }
        if let touch = transformTouch, touches.contains(touch) {
            transformTouch = nil
            onTransformEnded?()
            return
        }
        guard let touch = drawingTouch, touches.contains(touch) else { return }
        if strokeActive { onStrokeEnded?() }
        drawingTouch = nil
        strokeActive = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let pending = pendingSelectionTouch, touches.contains(pending.touch) {
            pendingSelectionTouch = nil
            return
        }
        if let touch = transformTouch, touches.contains(touch) {
            transformTouch = nil
            onTransformEnded?()
            return
        }
        guard let touch = drawingTouch, touches.contains(touch) else { return }
        cancelActiveStroke()
    }

    private func cancelActiveStroke() {
        if strokeActive { onStrokeCancelled?() }
        drawingTouch = nil
        strokeActive = false
    }
}
