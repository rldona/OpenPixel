import SwiftUI

/// Editor preferences that apply to every sprite, after Aseprite's Edit > Preferences.
/// Views read them with `@AppStorage` under these keys; model code uses the accessors.
/// https://www.aseprite.org/docs/preferences/
enum EditorSettings {
    /// Checker squares in sprite pixels; 0 sizes them with the zoom.
    static let checkerSizeKey = "checkerSize"
    /// Checker colors as `#RRGGBB`; empty follows the light or dark appearance.
    static let checkerLightKey = "checkerLight"
    static let checkerDarkKey = "checkerDark"
    /// Grid colors as `#RRGGBBAA` (the alpha is the opacity); empty uses the default.
    static let pixelGridColorKey = "pixelGridColor"
    static let tileGridColorKey = "tileGridColor"
    static let alphaFormatKey = "alphaFormat"
    /// Stopping playback goes back to the frame it started from.
    static let rewindOnStopKey = "rewindOnStop"
    static let undoLimitKey = "undoLimit"
    static let fingerInputKey = "fingerInput"
    static let pencilDoubleTapKey = "pencilDoubleTap"
    static let pencilSqueezeKey = "pencilSqueeze"
    /// Aseprite's Mirrored Default layout: tools on the right, panel on the left.
    static let mirroredLayoutKey = "mirroredLayout"

    static let checkerSizes = [0, 1, 2, 4, 8, 16]
    static let undoLimits = [25, 50, 100, 200, 500]
    static let defaultUndoLimit = 100

    private static var defaults: UserDefaults { .standard }

    static var undoLimit: Int {
        let value = defaults.integer(forKey: undoLimitKey)
        return value > 0 ? value : defaultUndoLimit
    }

    static var rewindOnStop: Bool { defaults.bool(forKey: rewindOnStopKey) }

    static var alphaFormat: AlphaFormat {
        AlphaFormat(rawValue: defaults.string(forKey: alphaFormatKey) ?? "") ?? .percent
    }

    /// Every editor preference goes back to its default.
    static func reset() {
        for key in [checkerSizeKey, checkerLightKey, checkerDarkKey, pixelGridColorKey, tileGridColorKey, alphaFormatKey,
                    rewindOnStopKey, undoLimitKey, fingerInputKey, pencilDoubleTapKey, pencilSqueezeKey, mirroredLayoutKey] {
            defaults.removeObject(forKey: key)
        }
    }
}

/// How alpha and opacity values are shown (Preferences > Color in Aseprite).
enum AlphaFormat: String, CaseIterable, Identifiable {
    /// 0–100 %.
    case percent
    /// 0–255.
    case byte

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .percent: "0–100 %"
        case .byte: "0–255"
        }
    }

    /// `alpha` goes from 0 to 1.
    func text(_ alpha: Double) -> String {
        let alpha = min(1, max(0, alpha))
        return switch self {
        case .percent: "\(Int((alpha * 100).rounded())) %"
        case .byte: "\(Int((alpha * 255).rounded()))"
        }
    }
}

/// What a finger does on the canvas.
enum FingerInput: String, CaseIterable, Identifiable {
    /// Draws until the Apple Pencil is used, then only moves the canvas.
    case automatic
    case draws
    /// Only moves and zooms the canvas.
    case navigates

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .automatic: "Draws until the Pencil is used"
        case .draws: "Always draws"
        case .navigates: "Only moves the canvas"
        }
    }
}

/// What an Apple Pencil double tap or squeeze does.
enum PencilAction: String, CaseIterable, Identifiable {
    /// Whatever the gesture is set to in iPadOS Settings (eraser, unless it's off).
    case system
    case eraser
    case swapColors
    case eyedropper
    case undo
    case nothing

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .system: "As in iPadOS Settings"
        case .eraser: "Switch to the eraser"
        case .swapColors: "Swap colors"
        case .eyedropper: "Switch to the eyedropper"
        case .undo: "Undo"
        case .nothing: "Nothing"
        }
    }
}

/// A color kept in `UserDefaults` as a hex string; empty means "use the default".
enum StoredColor {
    static func color(_ stored: String) -> PixelColor? {
        stored.isEmpty ? nil : PixelColor(hex: stored)
    }

    /// For a `ColorPicker`: the stored color, or `fallback` while there's none.
    static func binding(_ stored: Binding<String>, fallback: PixelColor) -> Binding<Color> {
        Binding(
            get: { (color(stored.wrappedValue) ?? fallback).color },
            set: {
                let c = PixelColor($0)
                stored.wrappedValue = String(format: "#%02X%02X%02X%02X", Int(c.r), Int(c.g), Int(c.b), Int(c.a))
            }
        )
    }
}
