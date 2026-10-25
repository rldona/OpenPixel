import Foundation
import Observation

/// A script's `Dialog`, shown as a floating window over the editor.
/// https://www.aseprite.org/api/dialog
@MainActor @Observable
final class ScriptDialog: Identifiable {
    enum Kind: String {
        case separator, label, slider, number, color, check, radio, button, combobox, entry, newrow
    }

    enum Value: Equatable {
        case bool(Bool)
        case number(Double)
        case text(String)
        case color(PixelColor)
    }

    struct Widget: Identifiable {
        let id = UUID()
        var kind: Kind
        /// The script's `id`, the key in `dlg.data`.
        var key: String?
        var label: String?
        var text: String?
        var min = 0.0
        var max = 100.0
        var decimals = 0
        var options: [String] = []
        var visible = true
        var enabled = true
        /// Lua registry references to the callbacks.
        var onClick: Int32?
        var onChange: Int32?
        /// Radios in a row are one group.
        var group = 0

        /// Where its value is kept: the script's id, or its own.
        var valueKey: String { key ?? id.uuidString }
    }

    let id = UUID()
    let title: String
    var widgets: [Widget] = []
    var values: [String: Value] = [:]
    var isOpen = false
    /// The button that closed it, `true` in `dlg.data`.
    @ObservationIgnored var closedBy: String?
    @ObservationIgnored var onClose: Int32?
    @ObservationIgnored weak var engine: ScriptEngine?

    init(title: String, engine: ScriptEngine) {
        self.title = title
        self.engine = engine
    }

    /// Aseprite lays widgets in rows: a labelled widget starts a row, the ones
    /// after it without a label stay on it (two radios, a row of buttons).
    var rows: [[Widget]] {
        var rows: [[Widget]] = []
        var breakNext = true
        for widget in widgets where widget.visible || widget.kind == .newrow {
            switch widget.kind {
            case .newrow:
                breakNext = true
            case .separator:
                rows.append([widget])
                breakNext = true
            default:
                if breakNext || widget.label != nil || rows.isEmpty {
                    rows.append([widget])
                } else {
                    rows[rows.count - 1].append(widget)
                }
                breakNext = false
            }
        }
        return rows
    }

    /// The label of a row: its first widget's.
    func label(of row: [Widget]) -> String? { row.first?.label }

    func number(_ widget: Widget) -> Double {
        if case .number(let n) = values[widget.valueKey] { return n }
        return widget.min
    }

    func bool(_ widget: Widget) -> Bool {
        if case .bool(let b) = values[widget.valueKey] { return b }
        return false
    }

    func text(_ widget: Widget) -> String {
        if case .text(let t) = values[widget.valueKey] { return t }
        return ""
    }

    func color(_ widget: Widget) -> PixelColor {
        if case .color(let c) = values[widget.valueKey] { return c }
        return .black
    }

    /// Selects a radio and clears the others in its group.
    func select(_ radio: Widget) {
        for other in widgets where other.kind == .radio && other.group == radio.group {
            values[other.valueKey] = .bool(other.id == radio.id)
        }
    }
}
