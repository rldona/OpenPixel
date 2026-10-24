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
    let spriteSize: CGSize
    let showGrid: Bool
    let mirrorX: Bool
    let onZoomChanged: (CGFloat) -> Void

    func makeUIView(context: Context) -> PixelCanvasView {
        let view = PixelCanvasView()
        view.document = document
        controller.view = view
        document.onCanvasChange = { [weak view] rect in view?.render(rect) }
        document.onOverlayChange = { [weak view] in view?.selectionChanged() }
        view.onTransformBegan = { [weak document] in document?.beginTransformDrag($0, at: $1) }
        view.onTransformMoved = { [weak document] in document?.continueTransformDrag(to: $0) }
        view.onTransformEnded = { [weak document] in document?.endTransformDrag() }
        view.onTransformOutsideTap = { [weak document] in document?.applyTransform() }
        view.onStrokeBegan = { [weak document] in document?.beginStroke(at: $0) }
        view.onStrokeMoved = { [weak document] in document?.continueStroke(through: $0) }
        view.onStrokeEnded = { [weak document] in document?.endStroke() }
        view.onStrokeCancelled = { [weak document] in document?.cancelStroke() }
        view.onUndo = { [weak document] in document?.undo() }
        view.onRedo = { [weak document] in document?.redo() }
        view.onEyedropper = { [weak document] in document?.pickColor(at: $0) }
        view.onPencilDoubleTap = { [weak document] in document?.toggleEraser() }
        return view
    }

    func updateUIView(_ view: PixelCanvasView, context: Context) {
        view.onZoomChanged = onZoomChanged
        view.spriteSize = spriteSize
        view.showGrid = showGrid
        view.mirrorX = mirrorX
        view.onionLayers = onionLayers
        if view.renderedRevision != revision || view.renderedFrame != frameIndex {
            view.renderAll()
        }
    }

    static func dismantleUIView(_ view: PixelCanvasView, coordinator: ()) {
        view.document?.onCanvasChange = nil
        view.document?.onOverlayChange = nil
    }
}
