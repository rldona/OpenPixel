import SwiftUI

/// Floating bar shown while something is selected: the common actions
/// within reach of a finger, since an iPad has no menu bar.
struct SelectionActionBar: View {
    let document: SpriteDocument

    var body: some View {
        HStack(spacing: 2) {
            barButton("Transform", "arrow.up.left.and.arrow.down.right") { document.beginTransform() }
            barButton("Duplicate and move", "plus.square.on.square") { document.beginTransform(copy: true) }
            divider
            barButton("Cut", "scissors") { document.cut() }
            barButton("Copy", "doc.on.doc") { document.copy() }
            barButton("Paste", "doc.on.clipboard") { document.paste() }
            barButton("Delete", "trash") { document.deleteSelection() }
            barButton("Fill with primary color", "paintbrush.pointed.fill") { document.fillSelection() }
            divider
            barButton("Flip horizontally", "arrow.left.and.right.righttriangle.left.righttriangle.right") { document.flip(horizontal: true) }
            barButton("Flip vertically", "arrow.up.and.down.righttriangle.up.righttriangle.down") { document.flip(horizontal: false) }
            barButton("Rotate 90° clockwise", "rotate.right") { document.rotate90(clockwise: true) }
            divider
            barButton("Invert selection", "square.on.square.intersection.dashed") { document.invertSelection() }
            barButton("Deselect", "xmark") { document.deselect() }
        }
        .floatingBarStyle()
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(width: 1, height: 22).padding(.horizontal, 4)
    }
}

/// Floating bar shown while pixels are being transformed.
struct TransformBar: View {
    @Bindable var document: SpriteDocument

    var body: some View {
        HStack(spacing: 2) {
            barButton("Flip horizontally", "arrow.left.and.right.righttriangle.left.righttriangle.right") { document.flip(horizontal: true) }
            barButton("Flip vertically", "arrow.up.and.down.righttriangle.up.righttriangle.down") { document.flip(horizontal: false) }
            barButton("Rotate 90° counterclockwise", "rotate.left") { document.rotate90(clockwise: false) }
            barButton("Rotate 90° clockwise", "rotate.right") { document.rotate90(clockwise: true) }
            Rectangle().fill(Theme.border).frame(width: 1, height: 22).padding(.horizontal, 4)

            toggle("Keep aspect", "lock", isOn: $document.keepAspect)
            toggle("Snap angle", "angle", isOn: $document.snapAngle)
            Menu {
                Picker("Rotation", selection: $document.rotationAlgorithm) {
                    Text("RotSprite").tag(RotationAlgorithm.rotSprite)
                    Text("Fast").tag(RotationAlgorithm.fast)
                }
            } label: {
                Text(document.rotationAlgorithm == .rotSprite ? "RotSprite" : "Fast")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 8)
                    .frame(height: 36)
            }
            .accessibilityLabel(Text("Rotation algorithm"))

            Text(verbatim: "\(document.transformInfo.width)×\(document.transformInfo.height) · \(document.transformInfo.degrees)°")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 8)
                .fixedSize()
            if document.transformExtraCels > 0 {
                // The other cels of the timeline range change when the transform is applied.
                Label {
                    document.transformExtraCels == 1 ? Text("+1 cel") : Text("+\(document.transformExtraCels) cels")
                } icon: {
                    Image(systemName: "square.stack.3d.up")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accentText)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 7))
                .fixedSize()
                .accessibilityLabel(Text("Also applies to \(document.transformExtraCels) more cels of the timeline selection"))
            }

            Button { document.cancelTransform() } label: {
                Text("Cancel")
                    .font(.system(size: 14, weight: .medium))
                    .fixedSize()
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Theme.chip, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            Button { document.applyTransform() } label: {
                Label("Apply", systemImage: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .fixedSize()
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .floatingBarStyle()
    }

    private func toggle(_ title: LocalizedStringKey, _ systemImage: String, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 40, height: 36)
                .foregroundStyle(isOn.wrappedValue ? Theme.onAccent : Theme.text)
                .background(isOn.wrappedValue ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }
}

/// The editor's Edit menu: clipboard, selection and canvas commands.
struct EditMenu: View {
    let document: SpriteDocument

    var body: some View {
        Menu {
            Section {
                Button("Cut", systemImage: "scissors") { document.cut() }
                Button("Copy", systemImage: "doc.on.doc") { document.copy() }
                Button("Paste", systemImage: "doc.on.clipboard") { document.paste() }
                Button("Delete", systemImage: "trash") { document.deleteSelection() }
                    .disabled(!document.hasSelection)
                Button("Fill with primary color", systemImage: "paintbrush.pointed.fill") { document.fillSelection() }
                Button("Replace color…", systemImage: "drop.halffull") { document.isReplacingColor = true }
                Button("New brush from selection", systemImage: "paintbrush.pointed") { document.newBrushFromSelection() }
                    .disabled(!document.hasSelection)
                Button("New layer from selection", systemImage: "square.on.square") { document.newLayerFromSelection(cut: false) }
                    .disabled(!document.hasSelection)
                Button("Cut to new layer", systemImage: "square.on.square.dashed") { document.newLayerFromSelection(cut: true) }
                    .disabled(!document.hasSelection)
            }
            Section {
                Button("Select all", systemImage: "rectangle.dashed") { document.selectAll() }
                Button("Deselect", systemImage: "xmark") { document.deselect() }
                    .disabled(!document.hasSelection)
                Button("Reselect", systemImage: "arrow.uturn.backward.square") { document.reselect() }
                Button("Invert selection", systemImage: "square.on.square.intersection.dashed") { document.invertSelection() }
                Button("Select layer content", systemImage: "square.3.layers.3d") { document.selectLayerContent() }
                Menu("Modify selection") {
                    ForEach([1, 2, 4], id: \.self) { n in
                        Button("Expand \(n) px") { document.expandSelection(by: n) }
                    }
                    ForEach([1, 2, 4], id: \.self) { n in
                        Button("Contract \(n) px") { document.contractSelection(by: n) }
                    }
                    ForEach([1, 2], id: \.self) { n in
                        Button("Border \(n) px") { document.borderSelection(n) }
                    }
                }
                .disabled(!document.hasSelection)
            }
            Section {
                Button("Transform", systemImage: "arrow.up.left.and.arrow.down.right") { document.beginTransform() }
                Button("Flip horizontally", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") { document.flip(horizontal: true) }
                Button("Flip vertically", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down") { document.flip(horizontal: false) }
                Button("Rotate 90° clockwise", systemImage: "rotate.right") { document.rotate90(clockwise: true) }
                Button("Rotate 90° counterclockwise", systemImage: "rotate.left") { document.rotate90(clockwise: false) }
            }
            Section("Canvas") {
                Button("Crop to selection", systemImage: "crop") { document.cropToSelection() }
                    .disabled(!document.hasSelection)
                Button("Trim empty space", systemImage: "rectangle.compress.vertical") { document.trimCanvas() }
                Menu("Rotate canvas") {
                    Button("90° clockwise") { document.rotateCanvas(clockwise: true) }
                    Button("90° counterclockwise") { document.rotateCanvas(clockwise: false) }
                    Button("180°") { document.rotateCanvas180() }
                }
                Menu("Flip canvas") {
                    Button("Horizontally") { document.flipCanvas(horizontal: true) }
                    Button("Vertically") { document.flipCanvas(horizontal: false) }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 40, height: 40)
                .foregroundStyle(Theme.text)
        }
        .accessibilityLabel(Text("Edit"))
    }
}

/// Aseprite's keyboard shortcuts for selection and transform, for iPads with a keyboard.
struct EditorShortcuts: View {
    let document: SpriteDocument

    var body: some View {
        Group {
            shortcut("x", .command) { document.cut() }
            shortcut("c", .command) { document.copy() }
            shortcut("v", .command) { document.paste() }
            shortcut("a", .command) { document.selectAll() }
            shortcut("d", .command) { document.deselect() }
            shortcut("d", [.command, .shift]) { document.reselect() }
            shortcut("i", [.command, .shift]) { document.invertSelection() }
            shortcut("t", .command) { document.beginTransform() }
            shortcut("b", .command) { document.newBrushFromSelection() }
            shortcut("j", .command) { document.newLayerFromSelection(cut: false) }
            shortcut("j", [.command, .shift]) { document.newLayerFromSelection(cut: true) }
            shortcut("h", .shift) { document.flip(horizontal: true) }
            shortcut("v", .shift) { document.flip(horizontal: false) }
            shortcut(.delete, []) { document.deleteSelection() }
            shortcut("r", .shift) { document.isReplacingColor = true }
            // Aseprite's X: swap primary and secondary colors (the button is in the side panel).
            shortcut("x", []) { document.swapColors() }
            if document.isTransforming {
                shortcut(.return, []) { document.applyTransform() }
                shortcut(.escape, []) { document.cancelTransform() }
                shortcut(.leftArrow, []) { document.nudgeTransform(dx: -1, dy: 0) }
                shortcut(.rightArrow, []) { document.nudgeTransform(dx: 1, dy: 0) }
                shortcut(.upArrow, []) { document.nudgeTransform(dx: 0, dy: -1) }
                shortcut(.downArrow, []) { document.nudgeTransform(dx: 0, dy: 1) }
            }
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func shortcut(_ key: KeyEquivalent, _ modifiers: EventModifiers, action: @escaping () -> Void) -> some View {
        Button(action: action) { EmptyView() }.keyboardShortcut(key, modifiers: modifiers)
    }
}

private func barButton(_ title: LocalizedStringKey, _ systemImage: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .medium))
            .frame(width: 42, height: 40)
            .foregroundStyle(Theme.text)
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text(title))
}

private extension View {
    func floatingBarStyle() -> some View {
        padding(.horizontal, 8)
            .frame(height: 50)
            .background(Theme.panel.opacity(0.96), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }
}
