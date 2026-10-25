import SwiftUI

/// A script's Dialog as a floating window, laid out in Aseprite's rows: the
/// row's label on the left, its widgets after it.
struct ScriptDialogView: View {
    let dialog: ScriptDialog
    /// The space it can be dragged in.
    let area: CGSize
    /// How far its starting place is from the area's right edge.
    let trailingInset: CGFloat
    @State private var editingColor: UUID?
    private static let labelWidth: CGFloat = 76

    var body: some View {
        let rows = dialog.rows
        FloatingWindow(Text(verbatim: dialog.title), id: "script.\(dialog.title)", area: area, trailingInset: trailingInset,
                       approximateHeight: CGFloat(rows.count) * 40 + 70) {
            Button { dialog.engine?.close(dialog) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.muted)
            .accessibilityLabel(Text("Close"))
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(rows, id: \.first?.id) { row in
                    rowView(row)
                }
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: [ScriptDialog.Widget]) -> some View {
        if let first = row.first, first.kind == .separator {
            HStack(spacing: 8) {
                if let text = first.text, !text.isEmpty {
                    Text(verbatim: text).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.muted).fixedSize()
                }
                Rectangle().fill(Theme.border).frame(height: 1)
            }
            .padding(.top, 2)
        } else {
            HStack(spacing: 8) {
                if let label = dialog.label(of: row) {
                    Text(verbatim: label)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: Self.labelWidth, alignment: .leading)
                }
                ForEach(row) { widget in
                    widgetView(widget)
                        .disabled(!widget.enabled)
                }
            }
        }
    }

    @ViewBuilder
    private func widgetView(_ widget: ScriptDialog.Widget) -> some View {
        switch widget.kind {
        case .label:
            Text(verbatim: dialog.text(widget)).font(.system(size: 13)).foregroundStyle(Theme.muted)
        case .slider:
            HStack(spacing: 8) {
                Slider(value: number(widget), in: widget.min...max(widget.min + 1, widget.max), step: 1) { editing in
                    if !editing { changed(widget) }
                }
                .tint(Theme.accent)
                Text(verbatim: "\(Int(dialog.number(widget).rounded()))")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 30, alignment: .trailing)
            }
        case .number:
            TextField("", value: number(widget), format: .number.precision(.fractionLength(widget.decimals)))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .onSubmit { changed(widget) }
        case .entry:
            TextField("", text: text(widget))
                .textFieldStyle(.roundedBorder)
                .onSubmit { changed(widget) }
        case .combobox:
            Picker(selection: Binding(get: { dialog.text(widget) }, set: { dialog.values[widget.valueKey] = .text($0); changed(widget) })) {
                ForEach(widget.options, id: \.self) { Text(verbatim: $0).tag($0) }
            } label: { EmptyView() }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .color:
            colorWell(widget)
        case .check:
            let isOn = dialog.bool(widget)
            Button {
                dialog.values[widget.valueKey] = .bool(!isOn)
                clicked(widget)
            } label: {
                Label { Text(verbatim: widget.text ?? "") } icon: { Image(systemName: isOn ? "checkmark.square.fill" : "square") }
                    .font(.system(size: 14))
                    .foregroundStyle(isOn ? Theme.accent : Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn ? .isSelected : [])
        case .radio:
            let isOn = dialog.bool(widget)
            Button {
                dialog.select(widget)
                clicked(widget)
            } label: {
                Text(verbatim: widget.text ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isOn ? Theme.accent : Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(isOn ? Theme.accentSoft : Theme.chip, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn ? .isSelected : [])
        case .button:
            // The dialog's first button is its main action.
            let isMain = dialog.widgets.first { $0.kind == .button }?.id == widget.id
            Button { clicked(widget) } label: {
                Text(verbatim: widget.text ?? "")
                    .font(.system(size: 15, weight: isMain ? .semibold : .regular))
                    .foregroundStyle(isMain ? Theme.onAccent : Theme.text)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(isMain ? Theme.accent : Theme.chip, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        case .separator, .newrow:
            EmptyView()
        }
    }

    private func colorWell(_ widget: ScriptDialog.Widget) -> some View {
        let color = dialog.color(widget)
        return Button { editingColor = widget.id } label: {
            HStack(spacing: 8) {
                ZStack {
                    Checkerboard(cell: 4)
                    color.color
                }
                .frame(width: 28, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.border))
                Text(verbatim: color.hex)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(get: { editingColor == widget.id }, set: { if !$0 { editingColor = nil; changed(widget) } })) {
            ColorEditor(color: Binding(get: { dialog.color(widget) }, set: { dialog.values[widget.valueKey] = .color($0) }),
                        palette: dialog.engine?.document?.structure.palette ?? [])
                .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel(Text(verbatim: widget.label ?? widget.text ?? ""))
        .accessibilityValue(Text(verbatim: color.hex))
    }

    private func number(_ widget: ScriptDialog.Widget) -> Binding<Double> {
        Binding(get: { dialog.number(widget) }, set: { dialog.values[widget.valueKey] = .number($0) })
    }

    private func text(_ widget: ScriptDialog.Widget) -> Binding<String> {
        Binding(get: { dialog.text(widget) }, set: { dialog.values[widget.valueKey] = .text($0) })
    }

    private func clicked(_ widget: ScriptDialog.Widget) { dialog.engine?.clicked(widget, in: dialog) }
    private func changed(_ widget: ScriptDialog.Widget) { dialog.engine?.changed(widget, in: dialog) }
}
