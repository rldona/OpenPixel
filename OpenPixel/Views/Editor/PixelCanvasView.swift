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
final class PixelCanvasView: UIView, UIGestureRecognizerDelegate, UIPencilInteractionDelegate {
    var spriteSize = CGSize(width: 32, height: 32) {
        didSet { if oldValue != spriteSize { needsFit = true; setNeedsLayout() } }
    }
    var image: CGImage? { didSet { setNeedsDisplay() } }
    var onionLayers: [OnionLayer] = [] { didSet { setNeedsDisplay() } }
    var showGrid = true { didSet { if oldValue != showGrid { setNeedsDisplay() } } }
    var mirrorX = false { didSet { if oldValue != mirrorX { setNeedsDisplay() } } }

    var onStrokeBegan: ((PixelPoint) -> Void)?
    var onStrokeMoved: ((PixelPoint) -> Void)?
    var onStrokeEnded: (() -> Void)?
    var onStrokeCancelled: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var onEyedropper: ((PixelPoint) -> Void)?
    var onPencilDoubleTap: (() -> Void)?
    var onZoomChanged: ((CGFloat) -> Void)?

    /// Screen points per sprite pixel.
    private(set) var scale: CGFloat = 1
    /// Top-left corner of the sprite in view coordinates.
    private var origin: CGPoint = .zero
    private var needsFit = true
    private var lastBoundsSize: CGSize = .zero
    private var pencilOnly = false
    private weak var drawingTouch: UITouch?
    private var strokeActive = false
    private var lastLocation: CGPoint?

    private static let minScale: CGFloat = 1
    private static let maxScale: CGFloat = 128
    private static let background = UIColor(red: 0x0F / 255, green: 0x0F / 255, blue: 0x12 / 255, alpha: 1)
    private static let checkerLight = UIColor(white: 0.27, alpha: 1)
    private static let checkerDark = UIColor(white: 0.21, alpha: 1)
    private static let accent = UIColor(red: 1, green: 0x7A / 255, blue: 0x59 / 255, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Self.background
        isMultipleTouchEnabled = true
        contentMode = .redraw
        setUpGestures()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

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

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.4
        longPress.allowedTouchTypes = fingers
        longPress.delegate = self
        addGestureRecognizer(longPress)

        let pencil = UIPencilInteraction()
        pencil.delegate = self
        addInteraction(pencil)
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
            setNeedsDisplay()
        }
        lastBoundsSize = bounds.size
    }

    /// Room kept free at the top for the floating tool options bar.
    private static let topInset: CGFloat = 72

    func fitToScreen() {
        let margin: CGFloat = 32
        let available = CGSize(width: bounds.width - margin * 2, height: bounds.height - Self.topInset - margin)
        let fit = min(available.width / spriteSize.width, available.height / spriteSize.height)
        scale = max(Self.minScale, min(Self.maxScale, fit >= 1 ? fit.rounded(.down) : fit))
        origin = CGPoint(
            x: ((bounds.width - spriteSize.width * scale) / 2).rounded(),
            y: (Self.topInset + (available.height - spriteSize.height * scale) / 2).rounded()
        )
        needsFit = false
        onZoomChanged?(scale)
        setNeedsDisplay()
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
        setNeedsDisplay()
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
        let t = g.translation(in: self)
        origin.x += t.x
        origin.y += t.y
        g.setTranslation(.zero, in: self)
        setNeedsDisplay()
    }

    @objc private func handleScroll(_ g: UIPanGestureRecognizer) {
        guard g.state == .changed else { return }
        let t = g.translation(in: self)
        origin.x += t.x
        origin.y += t.y
        g.setTranslation(.zero, in: self)
        setNeedsDisplay()
    }

    @objc private func handleUndoTap(_ g: UITapGestureRecognizer) {
        cancelActiveStroke()
        onUndo?()
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

    private func canDraw(with touch: UITouch) -> Bool {
        switch touch.type {
        case .pencil, .indirectPointer: true
        case .direct: !pencilOnly
        default: false
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
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
        let location = touch.location(in: self)
        lastLocation = location
        if let p = spritePoint(location) {
            strokeActive = true
            onStrokeBegan?(p)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = drawingTouch, touches.contains(touch) else { return }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            let location = sample.location(in: self)
            lastLocation = location
            guard let p = spritePoint(location) else { continue }
            if strokeActive {
                onStrokeMoved?(p)
            } else {
                strokeActive = true
                onStrokeBegan?(p)
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = drawingTouch, touches.contains(touch) else { return }
        if strokeActive { onStrokeEnded?() }
        drawingTouch = nil
        strokeActive = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = drawingTouch, touches.contains(touch) else { return }
        cancelActiveStroke()
    }

    private func cancelActiveStroke() {
        if strokeActive { onStrokeCancelled?() }
        drawingTouch = nil
        strokeActive = false
    }

    // MARK: - Rendering

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let spriteRect = CGRect(origin: origin, size: CGSize(width: spriteSize.width * scale, height: spriteSize.height * scale))
        let visible = spriteRect.intersection(bounds)

        ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 32, color: UIColor.black.withAlphaComponent(0.5).cgColor)
        ctx.setFillColor(Self.checkerLight.cgColor)
        ctx.fill(spriteRect)
        ctx.setShadow(offset: .zero, blur: 0)

        guard !visible.isNull else { return }
        ctx.saveGState()
        ctx.clip(to: visible)
        drawCheckerboard(in: visible, spriteRect: spriteRect, ctx: ctx)

        ctx.interpolationQuality = .none
        for onion in onionLayers {
            UIImage(cgImage: onion.image).draw(in: spriteRect, blendMode: .normal, alpha: onion.alpha)
        }
        if let image {
            UIImage(cgImage: image).draw(in: spriteRect)
        }
        if showGrid, scale >= 6 { drawGrid(in: visible, spriteRect: spriteRect, ctx: ctx) }
        ctx.restoreGState()

        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.12).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(spriteRect.insetBy(dx: -0.5, dy: -0.5))

        if mirrorX {
            ctx.setStrokeColor(Self.accent.cgColor)
            ctx.setLineWidth(2)
            ctx.setLineDash(phase: 0, lengths: [6, 5])
            ctx.move(to: CGPoint(x: spriteRect.midX, y: spriteRect.minY))
            ctx.addLine(to: CGPoint(x: spriteRect.midX, y: spriteRect.maxY))
            ctx.strokePath()
        }
    }

    /// Checker squares are a whole number of sprite pixels (1, 2, 4…) so they line up
    /// with the pixel grid; at high zoom each square is exactly one pixel.
    private func drawCheckerboard(in visible: CGRect, spriteRect: CGRect, ctx: CGContext) {
        var pixelsPerCell: CGFloat = 1
        while scale * pixelsPerCell < 8 { pixelsPerCell *= 2 }
        let cell = scale * pixelsPerCell
        ctx.setFillColor(Self.checkerDark.cgColor)
        let firstCol = Int(((visible.minX - spriteRect.minX) / cell).rounded(.down))
        let lastCol = Int(((visible.maxX - spriteRect.minX) / cell).rounded(.up))
        let firstRow = Int(((visible.minY - spriteRect.minY) / cell).rounded(.down))
        let lastRow = Int(((visible.maxY - spriteRect.minY) / cell).rounded(.up))
        guard firstCol <= lastCol, firstRow <= lastRow else { return }
        for row in firstRow...lastRow {
            for col in firstCol...lastCol where (row + col) % 2 == 0 {
                ctx.fill(CGRect(x: spriteRect.minX + CGFloat(col) * cell, y: spriteRect.minY + CGFloat(row) * cell, width: cell, height: cell))
            }
        }
    }

    private func drawGrid(in visible: CGRect, spriteRect: CGRect, ctx: CGContext) {
        let pixel = 1 / max(1, traitCollection.displayScale)
        ctx.setStrokeColor(UIColor(white: 1, alpha: 0.22).cgColor)
        ctx.setLineWidth(pixel)
        let firstX = max(1, Int(((visible.minX - spriteRect.minX) / scale).rounded(.down)))
        let lastX = min(Int(spriteSize.width) - 1, Int(((visible.maxX - spriteRect.minX) / scale).rounded(.up)))
        let firstY = max(1, Int(((visible.minY - spriteRect.minY) / scale).rounded(.down)))
        let lastY = min(Int(spriteSize.height) - 1, Int(((visible.maxY - spriteRect.minY) / scale).rounded(.up)))
        if firstX <= lastX {
            for x in firstX...lastX {
                let px = spriteRect.minX + CGFloat(x) * scale
                ctx.move(to: CGPoint(x: px, y: visible.minY))
                ctx.addLine(to: CGPoint(x: px, y: visible.maxY))
            }
        }
        if firstY <= lastY {
            for y in firstY...lastY {
                let py = spriteRect.minY + CGFloat(y) * scale
                ctx.move(to: CGPoint(x: visible.minX, y: py))
                ctx.addLine(to: CGPoint(x: visible.maxX, y: py))
            }
        }
        ctx.strokePath()
    }
}
