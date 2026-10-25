import SwiftUI
import UIKit

/// Color tokens. Each has a light and a dark value and follows the
/// appearance chosen in Preferences.
enum Theme {
    static let background = adaptive(light: 0xF2F2F5, dark: 0x0F0F12)
    static let panel = adaptive(light: 0xFFFFFF, dark: 0x18181C)
    static let card = adaptive(light: 0xFFFFFF, dark: 0x1A1A1F)
    static let raised = adaptive(light: 0xEEEEF2, dark: 0x1F1F25)
    static let field = adaptive(light: 0xF4F4F7, dark: 0x121215)
    static let chip = adaptive(light: 0xECECF1, dark: 0x26262D)
    static let selection = adaptive(light: 0xE3E3EA, dark: 0x2E2E37)
    static let rowActive = adaptive(light: 0xECECF1, dark: 0x222229)
    static let columnActive = adaptive(light: 0xE6E6EC, dark: 0x2A2A33)
    /// The timeline's header (frame numbers and layer buttons), set apart from the rows.
    static let timelineHeader = adaptive(light: 0xF1F1F5, dark: 0x202027)
    static let border = adaptive(light: 0xDCDCE2, dark: 0x2A2A31)
    static let strongBorder = adaptive(light: 0xC4C4CC, dark: 0x3A3A43)
    static let text = adaptive(light: 0x17171A, dark: 0xF2F2F5)
    static let muted = adaptive(light: 0x64646E, dark: 0xA1A1AA)
    static let dot = adaptive(light: 0x4A4A52, dark: 0xD4D4D8)
    /// The accent follows the color chosen in Preferences (`AccentChoice`).
    static let accent = accentToken(\.accent)
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x141417)
    /// Background of selected chips and toggles.
    static let accentSoft = accentToken(\.soft)
    /// Text on `accentSoft`.
    static let accentText = accentToken(\.text)
    static let checkerLight = adaptive(light: 0xE4E4E8, dark: 0x24242A)
    static let checkerDark = adaptive(light: 0xD6D6DC, dark: 0x2E2E36)

    /// Resolved each time it's drawn, so a new accent shows once the views are rebuilt.
    private static func accentToken(_ shade: KeyPath<AccentChoice.Shades, (light: UInt32, dark: UInt32)>) -> Color {
        Color(UIColor { traits in
            let pair = AccentChoice.current.shades[keyPath: shade]
            return UIColor(hex: traits.userInterfaceStyle == .dark ? pair.dark : pair.light)
        })
    }

    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat(hex >> 16 & 0xFF) / 255,
            green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double(hex >> 16 & 0xFF) / 255,
            green: Double(hex >> 8 & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Uppercase section label used across panels.
struct SectionLabel: View {
    let text: LocalizedStringKey

    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.muted)
    }
}

/// Square icon button with an optional selected state.
struct IconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    var isOn = false
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .medium))
                .frame(width: size, height: size)
                .foregroundStyle(isOn ? Theme.onAccent : Theme.text)
                .background(isOn ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Checkerboard used behind transparent pixels outside the canvas.
struct Checkerboard: View {
    var cell: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Theme.checkerLight))
            let cols = Int((size.width / cell).rounded(.up)), rows = Int((size.height / cell).rounded(.up))
            var path = Path()
            for row in 0..<rows {
                for col in 0..<cols where (row + col) % 2 == 0 {
                    path.addRect(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
                }
            }
            context.fill(path, with: .color(Theme.checkerDark))
        }
    }
}

/// A CGImage scaled with nearest-neighbour sampling over a checkerboard.
struct PixelThumbnail: View {
    let image: CGImage?

    var body: some View {
        ZStack {
            Checkerboard()
            if let image {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
            }
        }
    }
}

/// The OpenPixel wordmark drawn as pixel art, so it needs no bundled font.
struct PixelWordmark: View {
    var pixel: CGFloat = 3

    /// Glyphs 7 rows tall plus 2 for the descender of "p"; "#" is a lit pixel.
    private static let rows = 9
    private static let glyphs: [Character: [String]] = [
        "O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
        "p": ["....", "....", "###.", "#..#", "#..#", "#..#", "###.", "#...", "#..."],
        "e": ["....", "....", ".##.", "#..#", "####", "#...", ".###"],
        "n": ["....", "....", "###.", "#..#", "#..#", "#..#", "#..#"],
        "P": ["####.", "#...#", "#...#", "####.", "#....", "#....", "#...."],
        "i": ["#", ".", "#", "#", "#", "#", "#"],
        "x": [".....", ".....", "#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
        "l": ["#", "#", "#", "#", "#", "#", "#"]
    ]

    var body: some View {
        let word = Array("OpenPixel")
        let widths = word.map { Self.glyphs[$0]?.first?.count ?? 0 }
        let columns = widths.reduce(0, +) + word.count - 1
        Canvas { context, _ in
            var x = 0
            for (char, width) in zip(word, widths) {
                for (row, line) in (Self.glyphs[char] ?? []).enumerated() {
                    for (col, c) in line.enumerated() where c == "#" {
                        let rect = CGRect(x: CGFloat(x + col) * pixel, y: CGFloat(row) * pixel, width: pixel, height: pixel)
                        context.fill(Path(rect), with: .color(Theme.text))
                    }
                }
                x += width + 1
            }
        }
        .frame(width: CGFloat(columns) * pixel, height: CGFloat(Self.rows) * pixel)
        // Sit on the cap line, so the "p" descender hangs below the logo's centre.
        .padding(.top, 2 * pixel)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "OpenPixel"))
    }
}

/// The app icon's four colored squares.
struct PixelLogo: View {
    var size: CGFloat = 32

    var body: some View {
        let unit = size / 8
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: unit).fill(Color(hex: 0x1E1E23))
            square(0xFF7A59, x: 1, y: 1, unit: unit)
            square(0xFFCD75, x: 4, y: 1, unit: unit)
            square(0x41A6F6, x: 1, y: 4, unit: unit)
            square(0x38B764, x: 4, y: 4, unit: unit)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func square(_ hex: UInt32, x: Int, y: Int, unit: CGFloat) -> some View {
        Rectangle().fill(Color(hex: hex))
            .frame(width: unit * 3, height: unit * 3)
            .offset(x: CGFloat(x) * unit, y: CGFloat(y) * unit)
    }
}

/// An on/off option as a pill: the whole label is the touch target, and it
/// fills with the accent color when on. Used instead of switches in the
/// tool options and their popovers.
struct PillToggle: View {
    let title: LocalizedStringKey
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isOn ? Theme.accent : Theme.muted)
                Text(title).foregroundStyle(isOn ? Theme.accentText : Theme.text)
            }
            .font(.system(size: 13, weight: .medium))
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(isOn ? Theme.accentSoft : Theme.chip, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
