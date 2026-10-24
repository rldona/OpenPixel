import UIKit

/// How the text tool writes. Pixel fonts scale by whole pixels; system
/// fonts are drawn without antialiasing so every pixel is on or off.
struct TextStyle: Equatable, Sendable {
    enum Font: Hashable, Sendable {
        case pixel(String)
        /// A font family name; empty for the system font.
        case system(String)
    }

    enum Alignment: String, CaseIterable, Identifiable, Sendable {
        case left, center, right
        var id: String { rawValue }
    }

    var font = Font.pixel(PixelFont.standard.id)
    /// Pixel fonts: how many sprite pixels each font pixel takes.
    var scale = 1
    /// System fonts: size in sprite pixels.
    var pointSize = 16
    var letterSpacing = 1
    var lineSpacing = 1
    var alignment = Alignment.left
    /// A 1 px outline in the secondary color, common for game text.
    var outline = false

    /// Families offered for system fonts, besides the system font itself.
    static let systemFamilies = ["Helvetica Neue", "Avenir Next", "Menlo", "Courier New", "Georgia", "American Typewriter", "Chalkboard SE", "Marker Felt"]
}

enum TextRenderer {
    /// The largest text image, in pixels per side.
    static let maxSize = 1024

    /// Renders `text` as a tightly cropped image, or nil when it has no visible pixels.
    static func render(_ text: String, style: TextStyle, color: PixelColor, outlineColor: PixelColor) -> PixelImage? {
        var mask: Mask?
        switch style.font {
        case .pixel(let id):
            mask = pixelMask(text, font: PixelFont.named(id) ?? .standard, style: style)?.scaled(by: max(1, style.scale))
        case .system(let family):
            mask = systemMask(text, family: family, style: style)
        }
        guard var ink = mask?.trimmed() else { return nil }
        var outline: Mask?
        if style.outline {
            ink = ink.padded(by: 1)
            outline = ink.outline()
        }
        guard ink.width <= maxSize, ink.height <= maxSize else { return nil }
        var image = PixelImage(width: ink.width, height: ink.height)
        for i in ink.bits.indices {
            if ink.bits[i] { image.pixels[i] = color } else if outline?.bits[i] == true { image.pixels[i] = outlineColor }
        }
        return image
    }

    // MARK: Pixel fonts

    static func pixelMask(_ text: String, font: PixelFont, style: TextStyle) -> Mask? {
        let lines = text.components(separatedBy: .newlines)
        let spacing = max(0, style.letterSpacing)
        let widths = lines.map { line -> Int in
            var w = 0
            for (i, c) in line.enumerated() {
                if i > 0 { w += spacing }
                w += font.glyph(for: c)?.width ?? font.spaceWidth
            }
            return w
        }
        let lineHeight = font.ascent + font.descent, gap = max(0, style.lineSpacing)
        let width = widths.max() ?? 0, height = lines.count * lineHeight + (lines.count - 1) * gap
        guard width > 0, height > 0 else { return nil }
        var mask = Mask(width: width, height: height)
        for (n, line) in lines.enumerated() {
            let baseline = n * (lineHeight + gap) + font.ascent
            var x = switch style.alignment {
            case .left: 0
            case .center: (width - widths[n]) / 2
            case .right: width - widths[n]
            }
            for (i, c) in line.enumerated() {
                if i > 0 { x += spacing }
                guard let glyph = font.glyph(for: c) else {
                    x += font.spaceWidth
                    continue
                }
                let top = baseline - glyph.ascent
                for (r, row) in glyph.rows.enumerated() {
                    for (col, cell) in row.enumerated() where cell == "#" {
                        mask[x + col, top + r] = true
                    }
                }
                x += glyph.width
            }
        }
        return mask
    }

    // MARK: System fonts

    private static func systemMask(_ text: String, family: String, style: TextStyle) -> Mask? {
        let size = CGFloat(max(4, style.pointSize))
        let font = family.isEmpty
            ? UIFont.systemFont(ofSize: size)
            : UIFont(descriptor: UIFontDescriptor(fontAttributes: [.family: family]), size: size)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = switch style.alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        }
        paragraph.lineSpacing = CGFloat(style.lineSpacing)
        let string = NSAttributedString(string: text, attributes: [
            .font: font,
            .paragraphStyle: paragraph,
            .foregroundColor: UIColor.black,
            .kern: CGFloat(style.letterSpacing),
        ])
        let bounds = string.boundingRect(with: CGSize(width: maxSize, height: maxSize), options: [.usesLineFragmentOrigin], context: nil)
        let width = min(maxSize, Int(bounds.width.rounded(.up)) + 2), height = min(maxSize, Int(bounds.height.rounded(.up)) + 2)
        guard width > 2, height > 2 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            // Every pixel on or off: no smoothing at the edges.
            context.cgContext.setShouldAntialias(false)
            context.cgContext.setAllowsAntialiasing(false)
            context.cgContext.setShouldSmoothFonts(false)
            string.draw(with: CGRect(x: 1, y: 1, width: width - 2, height: height - 2), options: [.usesLineFragmentOrigin], context: nil)
        }
        guard let cgImage = rendered.cgImage, let image = PixelImage(cgImage: cgImage) else { return nil }
        var mask = Mask(width: image.width, height: image.height)
        for i in image.pixels.indices where image.pixels[i].a >= 128 { mask.bits[i] = true }
        return mask
    }

    // MARK: Mask

    struct Mask: Equatable {
        let width: Int
        let height: Int
        var bits: [Bool]

        init(width: Int, height: Int) {
            self.width = width
            self.height = height
            bits = Array(repeating: false, count: width * height)
        }

        subscript(x: Int, y: Int) -> Bool {
            get { x >= 0 && y >= 0 && x < width && y < height && bits[y * width + x] }
            set { if x >= 0 && y >= 0 && x < width && y < height { bits[y * width + x] = newValue } }
        }

        func scaled(by factor: Int) -> Mask {
            guard factor > 1 else { return self }
            var out = Mask(width: width * factor, height: height * factor)
            for y in 0..<out.height { for x in 0..<out.width { out.bits[y * out.width + x] = self[x / factor, y / factor] } }
            return out
        }

        /// Cropped to the pixels that are set, or nil when none is.
        func trimmed() -> Mask? {
            var minX = width, minY = height, maxX = -1, maxY = -1
            for y in 0..<height { for x in 0..<width where bits[y * width + x] {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            } }
            guard maxX >= 0 else { return nil }
            var out = Mask(width: maxX - minX + 1, height: maxY - minY + 1)
            for y in 0..<out.height { for x in 0..<out.width { out.bits[y * out.width + x] = self[x + minX, y + minY] } }
            return out
        }

        func padded(by n: Int) -> Mask {
            var out = Mask(width: width + 2 * n, height: height + 2 * n)
            for y in 0..<height { for x in 0..<width { out[x + n, y + n] = self[x, y] } }
            return out
        }

        /// Empty pixels touching set ones, diagonals included.
        func outline() -> Mask {
            var out = Mask(width: width, height: height)
            for y in 0..<height { for x in 0..<width where !self[x, y] {
                out[x, y] = (-1...1).contains { dy in (-1...1).contains { dx in self[x + dx, y + dy] } }
            } }
            return out
        }
    }
}
