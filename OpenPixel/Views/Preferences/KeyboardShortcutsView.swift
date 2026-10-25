import SwiftUI

/// Every keyboard shortcut, like Aseprite's Edit > Keyboard Shortcuts but read-only.
/// The keys follow Aseprite's defaults; they're bound where each action lives.
/// https://www.aseprite.org/docs/keyboard-shortcuts/
struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    /// Shown in its own sheet (from the editor), not pushed from Preferences.
    var showsDone = false

    struct Shortcut: Identifiable {
        let keys: String
        let title: LocalizedStringKey
        var id: String { keys + "\(title)" }
    }

    struct Group: Identifiable {
        let title: LocalizedStringKey
        let shortcuts: [Shortcut]
        var id: String { "\(title)" }
    }

    static var groups: [Group] {
        [
            Group(title: "Tools", shortcuts: Tool.allCases.map { tool in
                Shortcut(keys: (tool.shortcutModifiers.contains(.shift) ? "⇧" : "") + String(tool.shortcut.character).uppercased(), title: tool.title)
            } + [
                Shortcut(keys: "⌥", title: "Hold while tapping to pick a color"),
                Shortcut(keys: "⌃", title: "Hold while moving a selection to stretch it"),
                Shortcut(keys: "[  ]", title: "Smaller or bigger brush"),
                Shortcut(keys: "X", title: "Swap colors"),
            ]),
            Group(title: "Edit", shortcuts: [
                Shortcut(keys: "⌘Z", title: "Undo"),
                Shortcut(keys: "⇧⌘Z", title: "Redo"),
                Shortcut(keys: "⌘X", title: "Cut"),
                Shortcut(keys: "⌘C", title: "Copy"),
                Shortcut(keys: "⌘V", title: "Paste"),
                Shortcut(keys: "⌫", title: "Delete"),
                Shortcut(keys: "⌘T", title: "Transform"),
                Shortcut(keys: "⇧H", title: "Flip horizontal"),
                Shortcut(keys: "⇧V", title: "Flip vertical"),
                Shortcut(keys: "⇧R", title: "Replace color…"),
                Shortcut(keys: "⌘U", title: "Hue/Saturation…"),
                Shortcut(keys: "⌘B", title: "New brush from selection"),
                Shortcut(keys: "⌘J", title: "New layer from selection"),
                Shortcut(keys: "⇧⌘J", title: "Cut to new layer"),
            ]),
            Group(title: "Selection", shortcuts: [
                Shortcut(keys: "⌘A", title: "Select all"),
                Shortcut(keys: "⌘D", title: "Deselect"),
                Shortcut(keys: "⇧⌘D", title: "Reselect"),
                Shortcut(keys: "⇧⌘I", title: "Invert selection"),
                Shortcut(keys: "↩", title: "Apply the transform or finish the shape"),
                Shortcut(keys: "⎋", title: "Cancel the transform or the shape"),
                Shortcut(keys: "← → ↑ ↓", title: "Nudge while transforming"),
            ]),
            Group(title: "Animation", shortcuts: [
                Shortcut(keys: "↩", title: "Play or pause"),
                Shortcut(keys: ",  ←", title: "Previous frame"),
                Shortcut(keys: ".  →", title: "Next frame"),
                Shortcut(keys: "↖", title: "First frame"),
                Shortcut(keys: "↘", title: "Last frame"),
                Shortcut(keys: "⌥N", title: "New frame"),
                Shortcut(keys: "⌥⇧N", title: "New empty frame"),
                Shortcut(keys: "⌥⌘T", title: "New tag"),
                Shortcut(keys: "⇧N", title: "New layer"),
                Shortcut(keys: "⇧X", title: "Show or hide layer"),
            ]),
            Group(title: "View", shortcuts: [
                Shortcut(keys: "⌘+", title: "Zoom in"),
                Shortcut(keys: "⌘−", title: "Zoom out"),
                Shortcut(keys: "⌘0", title: "Fit to screen"),
                Shortcut(keys: "⌘1", title: "Actual size"),
                Shortcut(keys: "⌘'", title: "Pixel grid"),
                Shortcut(keys: "⇧⌘'", title: "Grid"),
                Shortcut(keys: "⇥", title: "Focus mode"),
                Shortcut(keys: "⇧⌘E", title: "Export"),
                Shortcut(keys: "⌘/", title: "Keyboard shortcuts"),
            ]),
            Group(title: "Projects", shortcuts: [
                Shortcut(keys: "⌘N", title: "New sprite"),
                Shortcut(keys: "⌘F", title: "Search"),
                Shortcut(keys: "⌘,", title: "Preferences"),
            ]),
        ]
    }

    var body: some View {
        List {
            ForEach(Self.groups) { group in
                Section(group.title) {
                    ForEach(group.shortcuts) { shortcut in
                        HStack {
                            Text(shortcut.title)
                            Spacer(minLength: 12)
                            Text(verbatim: shortcut.keys)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .navigationTitle("Keyboard shortcuts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDone {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
