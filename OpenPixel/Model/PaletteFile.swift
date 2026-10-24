import Foundation
import ImageIO

/// Palette files, the formats Aseprite and Lospec use.
enum PaletteFile {
    enum Format: String, CaseIterable, Identifiable {
        /// GIMP palette.
        case gpl
        /// One RRGGBB per line (Lospec's HEX file).
        case hex

        var id: String { rawValue }
        var title: String { self == .gpl ? "GIMP (.gpl)" : "Hex (.hex)" }
    }

    /// Extensions that can be imported. Images (.png, .gif) give their distinct colors.
    static let importExtensions = ["gpl", "hex", "pal", "txt", "png", "gif"]

    static let maxColors = 256

    /// Reads a palette from a file's contents; nil if no color could be read.
    static func colors(from data: Data, fileExtension: String) -> [PixelColor]? {
        let colors: [PixelColor]
        switch fileExtension.lowercased() {
        case "png", "gif":
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let image = PixelImage(cgImage: cgImage) else { return nil }
            var seen = Set<PixelColor>()
            colors = image.pixels.filter { $0.a != 0 && seen.insert($0).inserted }
        default:
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
            colors = parse(text)
        }
        return colors.isEmpty ? nil : Array(colors.prefix(maxColors))
    }

    /// Understands GIMP (.gpl), JASC (.pal), Paint.NET (.txt) and plain hex lists.
    static func parse(_ text: String) -> [PixelColor] {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return [] }

        if first.hasPrefix("JASC-PAL") {
            // JASC-PAL, 0100, count, then "r g b" lines.
            return lines.dropFirst(3).compactMap(rgbTriplet)
        }
        if first.hasPrefix("GIMP Palette") {
            return lines.dropFirst().compactMap { line in
                guard !line.hasPrefix("#"), !line.contains(":") else { return nil }
                return rgbTriplet(line)
            }
        }
        return lines.compactMap { line in
            guard !line.hasPrefix(";"), !line.hasPrefix("//") else { return nil }
            var hex = line.hasPrefix("#") ? String(line.dropFirst()) : line
            hex = String(hex.prefix { $0.isHexDigit })
            // Paint.NET writes AARRGGBB.
            if hex.count == 8 { hex = String(hex.dropFirst(2)) + String(hex.prefix(2)) }
            return PixelColor(hex: hex)
        }
    }

    private static func rgbTriplet(_ line: String) -> PixelColor? {
        let parts = line.split(whereSeparator: \.isWhitespace).prefix(3).compactMap { Int($0) }
        guard parts.count == 3, parts.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return PixelColor(r: UInt8(parts[0]), g: UInt8(parts[1]), b: UInt8(parts[2]))
    }

    static func data(_ colors: [PixelColor], name: String, format: Format) -> Data {
        let text: String
        switch format {
        case .gpl:
            let rows = colors.map { c in
                String(format: "%3d %3d %3d\t%@", Int(c.r), Int(c.g), Int(c.b), c.hex)
            }
            text = (["GIMP Palette", "Name: \(name)", "Columns: 8", "#"] + rows).joined(separator: "\n") + "\n"
        case .hex:
            text = colors.map { String($0.hex.dropFirst().prefix(6)).lowercased() }.joined(separator: "\n") + "\n"
        }
        return Data(text.utf8)
    }
}
