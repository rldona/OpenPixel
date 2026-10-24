import CoreGraphics
import Foundation

extension PixelImage {
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    func makeCGImage() -> CGImage? {
        Self.makeCGImage(pixels: pixels, width: width, height: height)
    }

    static func makeCGImage(pixels: [PixelColor], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: rgbaData(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: Self.colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// Reads any CGImage into non-premultiplied RGBA pixels.
    init?(cgImage: CGImage) {
        let width = cgImage.width, height = cgImage.height
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: Self.colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var pixels = [PixelColor]()
        pixels.reserveCapacity(width * height)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let a = bytes[i + 3]
            if a == 0 {
                pixels.append(.clear)
            } else {
                func unpremultiply(_ c: UInt8) -> UInt8 { UInt8(min(255, (Int(c) * 255 + Int(a) / 2) / Int(a))) }
                pixels.append(PixelColor(r: unpremultiply(bytes[i]), g: unpremultiply(bytes[i + 1]), b: unpremultiply(bytes[i + 2]), a: a))
            }
        }
        self.init(width: width, height: height, pixels: pixels)
    }
}
