import SwiftUI

/// Lets SwiftUI controls (zoom buttons) talk to the UIKit canvas.
@MainActor
final class CanvasController {
    fileprivate weak var view: PixelCanvasView?

    func zoomIn() { view?.zoom(by: 2) }
    func zoomOut() { view?.zoom(by: 0.5) }
    func fit() { view?.fitToScreen() }
}

struct PixelCanvas: UIViewRepresentable {
    let document: SpriteDocument
    let controller: CanvasController
    let image: CGImage?
    let onionLayers: [OnionLayer]
    let spriteSize: CGSize
    let showGrid: Bool
    let mirrorX: Bool
    let onZoomChanged: (CGFloat) -> Void

    func makeUIView(context: Context) -> PixelCanvasView {
        let view = PixelCanvasView()
        controller.view = view
        view.onStrokeBegan = { [weak document] in document?.beginStroke(at: $0) }
        view.onStrokeMoved = { [weak document] in document?.continueStroke(to: $0) }
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
        view.image = image
        view.onionLayers = onionLayers
        view.showGrid = showGrid
        view.mirrorX = mirrorX
    }
}
