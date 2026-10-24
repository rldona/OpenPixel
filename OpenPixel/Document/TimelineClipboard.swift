import Foundation

/// Copied cels, frames or layers from the timeline. It lives outside any
/// document, so blocks can be pasted into other sprites (Aseprite's
/// "Copy between documents"). https://www.aseprite.org/docs/timeline/#copy-between-documents
@MainActor @Observable
final class TimelineClipboard {
    static let shared = TimelineClipboard()

    enum Content {
        /// Rows from the top layer down, each with one cel per frame.
        case cels([[Sprite.CelContent]])
        /// Each frame's duration and its cels, from the bottom layer up.
        case frames([(duration: Int, cels: [Sprite.CelContent])])
        /// Bottom layer first, each with its cels by frame.
        case layers([(layer: Layer, cels: [Sprite.CelContent])])
    }

    var content: Content?

    var hasCels: Bool { if case .cels = content { true } else { false } }
    var hasFrames: Bool { if case .frames = content { true } else { false } }
    var hasLayers: Bool { if case .layers = content { true } else { false } }
}

extension Sprite.CelContent {
    /// The same cel for a canvas of another size: pixels keep their
    /// top-left position and whatever falls outside is cut.
    func fitted(width: Int, height: Int) -> Sprite.CelContent {
        guard let image, image.width != width || image.height != height else { return self }
        var fitted = PixelImage(width: width, height: height)
        fitted.paste(image, at: 0, 0)
        return Sprite.CelContent(image: fitted, opacity: opacity)
    }
}
