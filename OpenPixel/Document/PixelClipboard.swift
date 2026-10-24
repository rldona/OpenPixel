import UIKit
import UniformTypeIdentifiers

/// Copy and paste of pixels. Keeps the exact pixels and their position for
/// pasting inside OpenPixel, and puts a PNG on the system pasteboard so other
/// apps can paste it. Images copied in other apps can be pasted too.
@MainActor
enum PixelClipboard {
    private static var image: PixelImage?
    private static var origin = PixelPoint(x: 0, y: 0)
    /// The pasteboard's change count right after our own copy.
    private static var ownChangeCount = -1

    static func store(_ image: PixelImage, origin: PixelPoint) {
        self.image = image
        self.origin = origin
        if let data = try? Exporter.pngData(image) {
            UIPasteboard.general.setData(data, forPasteboardType: UTType.png.identifier)
        }
        ownChangeCount = UIPasteboard.general.changeCount
    }

    /// The pixels to paste and where they were copied from. Images from other
    /// apps get a negative origin, meaning "centre it".
    static func read(maxSize: Int) -> (PixelImage, PixelPoint)? {
        let board = UIPasteboard.general
        if let image, board.changeCount == ownChangeCount { return (image, origin) }
        if board.hasImages, let cgImage = board.image?.cgImage, let pasted = PixelImage(cgImage: cgImage),
           pasted.width <= maxSize, pasted.height <= maxSize {
            return (pasted, PixelPoint(x: -1, y: -1))
        }
        return image.map { ($0, origin) }
    }
}
