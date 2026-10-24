import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    case pencil, eraser, bucket, eyedropper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pencil: "Lápiz"
        case .eraser: "Goma"
        case .bucket: "Cubo de pintura"
        case .eyedropper: "Cuentagotas"
        }
    }

    var systemImage: String {
        switch self {
        case .pencil: "pencil"
        case .eraser: "eraser"
        case .bucket: "drop"
        case .eyedropper: "eyedropper"
        }
    }

    /// Same single-key shortcuts as Aseprite.
    var shortcut: KeyEquivalent {
        switch self {
        case .pencil: "b"
        case .eraser: "e"
        case .bucket: "g"
        case .eyedropper: "i"
        }
    }
}
