import SwiftUI

/// Edit > Replace Color (⇧R): swaps one color for another in the active cel
/// or in every cel, inside the selection when there is one.
/// https://www.aseprite.org/docs/replace-color/
struct ReplaceColorSheet: View {
    let document: SpriteDocument
    @State private var from: PixelColor
    @State private var to: PixelColor
    @State private var tolerance = 0.0
    @State private var everyCel = false
    @State private var editingFrom = false
    @State private var editingTo = false
    @Environment(\.dismiss) private var dismiss

    init(document: SpriteDocument) {
        self.document = document
        _from = State(initialValue: document.primary)
        _to = State(initialValue: document.secondary)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    colorRow("From", color: from, isEditing: $editingFrom) {
                        ColorEditor(color: $from, palette: document.sprite.palette)
                    }
                    colorRow("To", color: to, isEditing: $editingTo) {
                        ColorEditor(color: $to, palette: document.sprite.palette)
                    }
                    Button("Swap", systemImage: "arrow.up.arrow.down") { swap(&from, &to) }
                }
                Section {
                    VStack(alignment: .leading) {
                        LabeledContent("Tolerance") { Text(verbatim: "\(Int(tolerance))") }
                        Slider(value: $tolerance, in: 0...255, step: 1)
                    }
                } footer: {
                    Text("0 replaces only the exact color; higher values also replace similar ones.")
                }
                Section {
                    Picker("Where", selection: $everyCel) {
                        Text("Current cel").tag(false)
                        Text("Every cel").tag(true)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if document.hasSelection {
                        Text("Only inside the selection. Locked layers are left alone.")
                    } else {
                        Text("Locked layers are left alone.")
                    }
                }
            }
            .navigationTitle("Replace color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replace") {
                        let count = document.replaceColor(from, with: to, tolerance: Int(tolerance), everyCel: everyCel)
                        if count == 0, document.notice == nil {
                            document.notice = L10n.string("No pixels of that color")
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private func colorRow(_ title: LocalizedStringKey, color: PixelColor, isEditing: Binding<Bool>, @ViewBuilder editor: @escaping () -> some View) -> some View {
        Button { isEditing.wrappedValue = true } label: {
            HStack {
                Text(title).foregroundStyle(Theme.text)
                Spacer()
                Text(verbatim: color.hex).font(.system(.body, design: .monospaced)).foregroundStyle(Theme.muted)
                ZStack {
                    Checkerboard(cell: 5)
                    color.color
                }
                .frame(width: 36, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.border))
            }
        }
        .popover(isPresented: isEditing) {
            editor().presentationCompactAdaptation(.popover)
        }
    }
}
