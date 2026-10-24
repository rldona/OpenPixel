import SwiftUI

enum Theme {
    static let background = Color(hex: 0x0F0F12)
    static let panel = Color(hex: 0x18181C)
    static let raised = Color(hex: 0x1F1F25)
    static let field = Color(hex: 0x121215)
    static let selection = Color(hex: 0x2E2E37)
    static let border = Color(hex: 0x2A2A31)
    static let text = Color(hex: 0xF2F2F5)
    static let muted = Color(hex: 0xA1A1AA)
    static let accent = Color(hex: 0xFF7A59)
    static let onAccent = Color(hex: 0x141417)
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
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.muted)
    }
}

/// Square icon button with an optional selected state.
struct IconButton: View {
    let systemImage: String
    let label: String
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
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Checkerboard used behind transparent pixels outside the canvas.
struct Checkerboard: View {
    var cell: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: 0x24242A)))
            let cols = Int((size.width / cell).rounded(.up)), rows = Int((size.height / cell).rounded(.up))
            var path = Path()
            for row in 0..<rows {
                for col in 0..<cols where (row + col) % 2 == 0 {
                    path.addRect(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
                }
            }
            context.fill(path, with: .color(Color(hex: 0x2E2E36)))
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
