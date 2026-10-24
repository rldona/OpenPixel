import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    case pencil, eraser, bucket, eyedropper, line, rectangle, ellipse

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pencil: "Lápiz"
        case .eraser: "Goma"
        case .bucket: "Cubo de pintura"
        case .eyedropper: "Cuentagotas"
        case .line: "Línea"
        case .rectangle: "Rectángulo"
        case .ellipse: "Elipse"
        }
    }

    var systemImage: String {
        switch self {
        case .pencil: "pencil"
        case .eraser: "eraser"
        case .bucket: "drop"
        case .eyedropper: "eyedropper"
        case .line: "line.diagonal"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        }
    }

    /// Same shortcuts as Aseprite.
    var shortcut: KeyEquivalent {
        switch self {
        case .pencil: "b"
        case .eraser: "e"
        case .bucket: "g"
        case .eyedropper: "i"
        case .line: "l"
        case .rectangle, .ellipse: "u"
        }
    }

    var shortcutModifiers: EventModifiers { self == .ellipse ? .shift : [] }

    /// Tools whose strokes are stamped with the brush.
    var usesBrush: Bool {
        switch self {
        case .pencil, .eraser, .line, .rectangle, .ellipse: true
        case .bucket, .eyedropper: false
        }
    }

    /// Tools that draw a shape from the touch-down point to the current point.
    var isShape: Bool { self == .line || self == .rectangle || self == .ellipse }
}
