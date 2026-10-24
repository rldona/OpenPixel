import SwiftUI

/// Lets SwiftUI controls (zoom buttons) talk to the UIKit canvas.
@MainActor
final class CanvasController {
    fileprivate weak var view: PixelCanvasView?

    func zoomIn() { view?.zoom(by: 2) }
    func zoomOut() { view?.zoom(by: 0.5) }
    func fit() { view?.fitToScreen() }
}

/// SwiftUI only redraws the canvas for committed changes (`revision`) and frame
/// changes. While a stroke is in progress the document notifies the canvas
/// directly with the area that changed, without going through SwiftUI.
struct PixelCanvas: UIViewRepresentable {
    let document: SpriteDocument
    let controller: CanvasController
    let revision: Int
    let frameIndex: Int
    let onionLayers: [OnionLayer]
    let references: [ReferenceOverlay]
    let spriteSize: CGSize
    let showGrid: Bool
    let tileGrid: GridSettings?
    let symmetry: Symmetry
    let tiledMode: TiledMode
    let onZoomChanged: (CGFloat) -> Void
    var onFocusToggle: () -> Void = {}

    func makeUIView(context: Context) -> PixelCanvasView {
        let view = PixelCanvasView()
        view.document = document
        controller.view = view
        connect(view)
        view.onTransformBegan = { [weak document] in document?.beginTransformDrag($0, at: $1) }
        view.onTransformMoved = { [weak document] in document?.continueTransformDrag(to: $0) }
        view.onTransformEnded = { [weak document] in document?.endTransformDrag() }
        view.onTransformOutsideTap = { [weak document] in document?.applyTransform() }
        view.onStrokeBegan = { [weak document] in document?.beginStroke(at: $0, pressure: $1) }
        view.onStrokeMoved = { [weak document] in document?.continueStroke(through: $0, pressures: $1) }
        view.onStrokeEnded = { [weak document] in document?.endStroke() }
        view.onStrokeCancelled = { [weak document] in document?.cancelStroke() }
        view.onUndo = { [weak document] in document?.undo() }
        view.onRedo = { [weak document] in document?.redo() }
        view.onEyedropper = { [weak document] in document?.pickColor(at: $0) }
        view.onPencilDoubleTap = { [weak document] in document?.toggleEraser() }
        // Aseprite paints with the secondary color on right-click; on iPad a squeeze swaps the colors.
        view.onPencilSqueeze = { [weak document] in document?.swapColors() }
        view.onSymmetryAxisMoved = { [weak document] in document?.moveSymmetryAxis(vertical: $0, to: $1) }
        return view
    }

    /// Live updates (strokes, transforms) reach the canvas through these
    /// callbacks, not through SwiftUI. Only one canvas owns them, so a canvas
    /// being torn down can't disconnect the one that replaced it.
    private func connect(_ view: PixelCanvasView) {
        controller.view = view
        document.canvasOwner = view
        document.onCanvasChange = { [weak view] rect in view?.render(rect) }
        document.onOverlayChange = { [weak view] in view?.selectionChanged() }
    }

    func updateUIView(_ view: PixelCanvasView, context: Context) {
        if document.canvasOwner !== view { connect(view) }
        view.onZoomChanged = onZoomChanged
        view.onFocusToggle = onFocusToggle
        view.spriteSize = spriteSize
        view.showGrid = showGrid
        view.tileGrid = tileGrid
        view.symmetry = symmetry
        view.tiledMode = tiledMode
        view.onionLayers = onionLayers
        view.references = references
        if view.renderedRevision != revision || view.renderedFrame != frameIndex {
            view.renderAll()
        }
    }

    static func dismantleUIView(_ view: PixelCanvasView, coordinator: ()) {
        guard let document = view.document, document.canvasOwner === view else { return }
        document.onCanvasChange = nil
        document.onOverlayChange = nil
        document.canvasOwner = nil
    }
}
