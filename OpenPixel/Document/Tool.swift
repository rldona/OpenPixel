import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    case pencil, eraser, bucket, eyedropper, line, rectangle, ellipse
    case selectRectangle, selectEllipse, lasso, magicWand, move, text

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .pencil: "Pencil"
        case .eraser: "Eraser"
        case .bucket: "Paint bucket"
        case .eyedropper: "Eyedropper"
        case .line: "Line"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .selectRectangle: "Rectangular marquee"
        case .selectEllipse: "Elliptical marquee"
        case .lasso: "Lasso"
        case .magicWand: "Magic wand"
        case .move: "Move"
        case .text: "Text"
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
        case .selectRectangle: "rectangle.dashed"
        case .selectEllipse: "circle.dashed"
        case .lasso: "lasso"
        case .magicWand: "wand.and.stars"
        case .move: "arrow.up.and.down.and.arrow.left.and.right"
        case .text: "textformat"
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
        case .selectRectangle, .selectEllipse: "m"
        case .lasso: "q"
        case .magicWand: "w"
        case .move: "v"
        case .text: "t"
        }
    }

    var shortcutModifiers: EventModifiers { self == .ellipse || self == .selectEllipse ? .shift : [] }

    /// Tools whose strokes are stamped with the brush.
    var usesBrush: Bool {
        switch self {
        case .pencil, .eraser, .line, .rectangle, .ellipse: true
        default: false
        }
    }

    /// Tools that draw a shape from the touch-down point to the current point.
    var isShape: Bool { self == .line || self == .rectangle || self == .ellipse }

    /// Tools that change the selection instead of pixels.
    var isSelection: Bool { [.selectRectangle, .selectEllipse, .lasso, .magicWand].contains(self) }
}

/// Tools that share one slot in the tool rail: tap uses the group's current
/// tool, touch and hold lists the others.
enum ToolGroup: CaseIterable, Identifiable {
    case pencil, eraser, bucket, eyedropper, shapes, text, select, move

    var id: Self { self }

    var tools: [Tool] {
        switch self {
        case .pencil: [.pencil]
        case .eraser: [.eraser]
        case .bucket: [.bucket]
        case .eyedropper: [.eyedropper]
        case .shapes: [.line, .rectangle, .ellipse]
        case .text: [.text]
        case .select: [.selectRectangle, .selectEllipse, .lasso, .magicWand]
        case .move: [.move]
        }
    }

    static func of(_ tool: Tool) -> ToolGroup {
        allCases.first { $0.tools.contains(tool) }!
    }
}
