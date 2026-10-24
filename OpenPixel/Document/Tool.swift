import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
    case pencil, spray, eraser, bucket, gradient, eyedropper, line, curve, rectangle, ellipse, contour, polygon
    case selectRectangle, selectEllipse, lasso, magicWand, move, slice, text

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .pencil: "Pencil"
        case .spray: "Spray"
        case .eraser: "Eraser"
        case .bucket: "Paint bucket"
        case .gradient: "Gradient"
        case .eyedropper: "Eyedropper"
        case .line: "Line"
        case .curve: "Curve"
        case .contour: "Contour"
        case .polygon: "Polygon"
        case .rectangle: "Rectangle"
        case .ellipse: "Ellipse"
        case .selectRectangle: "Rectangular marquee"
        case .selectEllipse: "Elliptical marquee"
        case .lasso: "Lasso"
        case .magicWand: "Magic wand"
        case .move: "Move"
        case .slice: "Slice"
        case .text: "Text"
        }
    }

    var systemImage: String {
        switch self {
        case .pencil: "pencil"
        case .spray: "aqi.medium"
        case .eraser: "eraser"
        case .bucket: "drop"
        case .gradient: "square.lefthalf.filled"
        case .eyedropper: "eyedropper"
        case .line: "line.diagonal"
        case .curve: "point.topleft.down.to.point.bottomright.curvepath"
        case .contour: "scribble.variable"
        case .polygon: "pentagon"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .selectRectangle: "rectangle.dashed"
        case .selectEllipse: "circle.dashed"
        case .lasso: "lasso"
        case .magicWand: "wand.and.stars"
        case .move: "arrow.up.and.down.and.arrow.left.and.right"
        case .slice: "rectangle.split.3x3"
        case .text: "textformat"
        }
    }

    /// Same shortcuts as Aseprite.
    var shortcut: KeyEquivalent {
        switch self {
        case .pencil: "b"
        case .spray: "s"
        case .eraser: "e"
        case .bucket, .gradient: "g"
        case .eyedropper: "i"
        case .line, .curve: "l"
        case .contour, .polygon: "d"
        case .rectangle, .ellipse: "u"
        case .selectRectangle, .selectEllipse: "m"
        case .lasso: "q"
        case .magicWand: "w"
        case .move: "v"
        case .slice: "c"
        case .text: "t"
        }
    }

    var shortcutModifiers: EventModifiers { [.ellipse, .selectEllipse, .curve, .polygon, .gradient, .spray, .slice].contains(self) ? .shift : [] }

    /// Tools whose strokes are stamped with the brush.
    var usesBrush: Bool {
        switch self {
        case .pencil, .eraser, .line, .curve, .rectangle, .ellipse: true
        default: false
        }
    }

    /// Tools that paint with the ink (the eraser always erases).
    var usesInk: Bool { (usesBrush && self != .eraser) || [.spray, .bucket, .gradient, .contour, .polygon].contains(self) }

    /// Shapes built over several touches: a curve is bent after drawing its
    /// line, a polygon gets a corner per tap.
    var buildsOverTouches: Bool { self == .curve || self == .polygon }

    /// Tools that draw a shape from the touch-down point to the current point.
    var isShape: Bool { [.line, .rectangle, .ellipse, .gradient].contains(self) }

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
        case .pencil: [.pencil, .spray]
        case .eraser: [.eraser]
        case .bucket: [.bucket, .gradient]
        case .eyedropper: [.eyedropper]
        case .shapes: [.line, .curve, .rectangle, .ellipse, .contour, .polygon]
        case .text: [.text]
        case .select: [.selectRectangle, .selectEllipse, .lasso, .magicWand]
        case .move: [.move, .slice]
        }
    }

    static func of(_ tool: Tool) -> ToolGroup {
        allCases.first { $0.tools.contains(tool) }!
    }
}
