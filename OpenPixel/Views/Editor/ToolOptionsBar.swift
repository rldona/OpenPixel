import SwiftUI

/// Floating bar over the canvas with the active tool's options (Pixaki-style).
struct ToolOptionsBar: View {
    @Bindable var document: SpriteDocument

    var body: some View {
        // When a tool has more options than fit, the bar scrolls sideways.
        ViewThatFits(in: .horizontal) {
            items.padding(.horizontal, 12)
            ScrollView(.horizontal, showsIndicators: false) {
                items.padding(.horizontal, 12)
            }
        }
        .frame(height: 44)
        .background(Theme.panel.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        .background {
            // Common shortcut for brush size in drawing apps.
            Group {
                Button("Smaller brush") { document.setBrushSize(document.brushSize - 1) }
                    .keyboardShortcut("[", modifiers: [])
                Button("Bigger brush") { document.setBrushSize(document.brushSize + 1) }
                    .keyboardShortcut("]", modifiers: [])
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private var items: some View {
        HStack(spacing: 10) {
            Label(document.tool.title, systemImage: document.tool.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.text)
                .fixedSize()

            if document.tool.usesBrush {
                divider
                if !usingCustomBrush { brushSize }
                // The tip's shape only shows from 2 px up (or when there's a custom brush to pick).
                if document.brushSize > 1 || document.customBrush != nil { brushShape }
                if document.brushShape == .line && !usingCustomBrush && document.brushSize > 1 { brushAngle }
                if usingCustomBrush && document.tool != .eraser {
                    toggle("Use color", isOn: $document.customBrushUsesColor)
                }
            }
            if document.tool == .spray {
                divider
                stepper(value: $document.sprayWidth, range: 1...32, label: "Width", unit: "px")
                stepper(value: $document.spraySpeed, range: 1...32, label: "Speed", unit: nil)
            }
            if document.tool.usesInk || document.tool == .eraser {
                divider
                InkButton(document: document)
            }
            if document.tool == .pencil || document.tool == .eraser {
                toggle("Pixel-perfect", isOn: $document.pixelPerfect)
                    .disabled(document.brushSize > 1)
                    .opacity(document.brushSize > 1 ? 0.4 : 1)
            }
            if document.tool == .rectangle || document.tool == .ellipse {
                divider
                toggle("Fill", isOn: $document.shapeFilled)
            }
            if document.tool == .rectangle {
                cornerRadius
            }
            if document.tool.buildsOverTouches || document.tool == .contour {
                divider
                shapeProgress
            }
            if document.tool == .gradient {
                divider
                gradientOptions
            }
            if document.tool == .bucket || document.tool == .gradient {
                divider
                tolerance($document.fillTolerance)
                toggle("Contiguous", isOn: $document.fillContiguous)
                if document.fillContiguous { toggle("Diagonals", isOn: $document.fillDiagonal) }
                toggle("All layers", isOn: $document.fillSampleAllLayers)
            }
            if document.tool == .eyedropper {
                divider
                toggle("Active layer only", isOn: $document.eyedropperActiveLayer)
                ViewThatFits(in: .horizontal) {
                    Text("Tap the canvas to pick a color")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize()
                    Color.clear.frame(width: 0, height: 0)
                }
            }
            if document.tool.isSelection {
                divider
                selectionModes
                if document.tool != .magicWand {
                    divider
                    toggle("Fit to content", isOn: $document.selectionFitsContent)
                }
                toggle("All frames", isOn: $document.selectionAllFrames)
                if document.tool != .magicWand {
                    // The hint gives way when the bar runs out of room.
                    ViewThatFits(in: .horizontal) {
                        Group {
                            if document.hasSelection && document.selectionMode == .replace {
                                Text("Drag inside to move")
                            } else {
                                Text("Tap an element to select it")
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .fixedSize()
                        Color.clear.frame(width: 0, height: 0)
                    }
                }
            }
            if document.tool == .magicWand {
                divider
                tolerance($document.wandTolerance)
                toggle("Contiguous", isOn: $document.wandContiguous)
                toggle("All layers", isOn: $document.wandSampleAllLayers)
            }
            if document.tool == .text {
                divider
                textOptions
            }
            if document.tool == .move {
                Text("Drag to move the selection or the layer content")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .fixedSize()
            }
        }
        .frame(height: 44)
    }

    /// Replace / add / subtract / intersect. On a keyboard-less iPad these
    /// replace Aseprite's Shift and Alt modifiers.
    private var selectionModes: some View {
        HStack(spacing: 2) {
            ForEach(SelectionMode.allCases) { mode in
                Button { document.selectionMode = mode } label: {
                    Image(systemName: icon(for: mode))
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 36, height: 30)
                        .foregroundStyle(document.selectionMode == mode ? Theme.onAccent : Theme.text)
                        .background(document.selectionMode == mode ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(title(for: mode)))
                .accessibilityAddTraits(document.selectionMode == mode ? .isSelected : [])
            }
        }
    }

    private func icon(for mode: SelectionMode) -> String {
        switch mode {
        case .replace: "square.dashed"
        case .add: "plus.square.dashed"
        case .subtract: "minus.square"
        case .intersect: "square.on.square.intersection.dashed"
        }
    }

    private func title(for mode: SelectionMode) -> LocalizedStringKey {
        switch mode {
        case .replace: "Replace selection"
        case .add: "Add to selection"
        case .subtract: "Subtract from selection"
        case .intersect: "Intersect selection"
        }
    }

    private var gradientOptions: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                ForEach(GradientShape.allCases) { shape in
                    Button { document.gradientShape = shape } label: {
                        Image(systemName: shape == .linear ? "square.lefthalf.filled" : "circle.circle")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 36, height: 30)
                            .foregroundStyle(document.gradientShape == shape ? Theme.onAccent : Theme.text)
                            .background(document.gradientShape == shape ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(shape == .linear ? Text("Linear gradient") : Text("Radial gradient"))
                    .accessibilityAddTraits(document.gradientShape == shape ? .isSelected : [])
                }
            }
            Menu {
                Picker("Dithering", selection: $document.gradientDither) {
                    ForEach(GradientDither.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkerboard.rectangle")
                    Text(document.gradientDither.title)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text)
                .fixedSize()
            }
            .accessibilityLabel(Text("Dithering"))
        }
    }

    private var cornerRadius: some View {
        HStack(spacing: 2) {
            Image(systemName: "button.roundedtop.horizontal")
                .font(.system(size: 13, weight: .medium))
                .accessibilityHidden(true)
            Button { document.cornerRadius = max(0, document.cornerRadius - 1) } label: {
                Image(systemName: "minus").frame(width: 30, height: 34)
            }
            .disabled(document.cornerRadius == 0)
            .accessibilityLabel(Text("Less rounded corners"))
            Text(verbatim: "\(document.cornerRadius) px")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(width: 40)
                .accessibilityLabel(Text("Corner radius: \(document.cornerRadius) pixels"))
            Button { document.cornerRadius = min(SpriteDocument.maxCornerRadius, document.cornerRadius + 1) } label: {
                Image(systemName: "plus").frame(width: 30, height: 34)
            }
            .accessibilityLabel(Text("More rounded corners"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
    }

    /// What the next touch does while a curve or polygon is being built, and a Done button.
    @ViewBuilder
    private var shapeProgress: some View {
        Text(shapeHint)
            .font(.system(size: 13))
            .foregroundStyle(Theme.muted)
            .fixedSize()
        if document.isBuildingShape {
            Button { document.finishPendingShape() } label: {
                Text("Done")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [])
            Button { document.cancelPendingShape() } label: {
                Image(systemName: "xmark").frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.text)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel(Text("Cancel"))
        }
    }

    private var shapeHint: LocalizedStringKey {
        switch (document.tool, document.pendingShapeStage) {
        case (.curve, 2): "Drag to bend the curve"
        case (.curve, 3): "Drag to bend the other end"
        case (.curve, _): "Drag to draw the line, then bend it"
        case (.polygon, 0): "Tap to place the corners"
        case (.polygon, _): "Tap the first corner to close it"
        default: "Draw the outline; it fills when you lift"
        }
    }

    private func tolerance(_ value: Binding<Int>) -> some View {
        HStack(spacing: 2) {
            Text("Tolerance").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).fixedSize()
            Button { value.wrappedValue = max(0, value.wrappedValue - 8) } label: {
                Image(systemName: "minus").frame(width: 30, height: 34)
            }
            .accessibilityLabel(Text("Lower tolerance"))
            Text(verbatim: "\(value.wrappedValue)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(width: 34)
            Button { value.wrappedValue = min(255, value.wrappedValue + 8) } label: {
                Image(systemName: "plus").frame(width: 30, height: 34)
            }
            .accessibilityLabel(Text("Higher tolerance"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
    }

    /// Font, size and outline; the rest is in the sheet that opens on tapping the canvas.
    private var textOptions: some View {
        HStack(spacing: 10) {
            Menu {
                TextFontPicker(style: $document.textStyle)
            } label: {
                HStack(spacing: 4) {
                    Text(verbatim: document.textStyle.fontName)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text)
                .fixedSize()
            }
            .accessibilityLabel(Text("Font"))
            HStack(spacing: 2) {
                Button { adjustTextSize(-1) } label: { Image(systemName: "minus").frame(width: 30, height: 34) }
                    .accessibilityLabel(Text("Smaller text"))
                Text(verbatim: document.textStyle.sizeLabel)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .frame(minWidth: 40)
                Button { adjustTextSize(1) } label: { Image(systemName: "plus").frame(width: 30, height: 34) }
                    .accessibilityLabel(Text("Bigger text"))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.text)
            toggle("Outline", isOn: $document.textStyle.outline)
            Text("Tap the canvas to write")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize()
        }
    }

    private func adjustTextSize(_ direction: Int) {
        if case .pixel = document.textStyle.font {
            document.textStyle.scale = min(8, max(1, document.textStyle.scale + direction))
        } else {
            document.textStyle.pointSize = min(128, max(6, document.textStyle.pointSize + 2 * direction))
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(width: 1, height: 22)
    }

    private var brushSize: some View {
        HStack(spacing: 2) {
            Button { document.setBrushSize(document.brushSize - 1) } label: {
                Image(systemName: "minus").frame(width: 32, height: 34)
            }
            .disabled(document.brushSize <= 1)
            .accessibilityLabel(Text("Smaller brush"))
            Text(verbatim: "\(document.brushSize) px")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(width: 44)
                .accessibilityLabel(Text("Brush size: \(document.brushSize) pixels"))
            Button { document.setBrushSize(document.brushSize + 1) } label: {
                Image(systemName: "plus").frame(width: 32, height: 34)
            }
            .disabled(document.brushSize >= SpriteDocument.maxBrushSize)
            .accessibilityLabel(Text("Bigger brush"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
    }

    private var usingCustomBrush: Bool { document.useCustomBrush && document.customBrush != nil }

    private var brushShape: some View {
        HStack(spacing: 2) {
            ForEach(BrushShape.allCases) { shape in
                let isOn = !usingCustomBrush && document.brushShape == shape
                Button {
                    document.brushShape = shape
                    document.useCustomBrush = false
                } label: {
                    Image(systemName: icon(for: shape))
                        .accessibilityHidden(true)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 32, height: 30)
                        .foregroundStyle(isOn ? Theme.onAccent : Theme.muted)
                        .background(isOn ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title(for: shape))
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
            if let brush = document.customBrush, let image = brush.makeCGImage() {
                Button { document.useCustomBrush = true } label: {
                    Image(decorative: image, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .frame(width: 32, height: 30)
                        .background(usingCustomBrush ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(usingCustomBrush ? Theme.accent : .clear, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Custom brush"))
                .accessibilityAddTraits(usingCustomBrush ? .isSelected : [])
            }
        }
    }

    private func icon(for shape: BrushShape) -> String {
        switch shape {
        case .square: "square.fill"
        case .circle: "circle.fill"
        case .line: "line.diagonal"
        }
    }

    private func title(for shape: BrushShape) -> Text {
        switch shape {
        case .square: Text("Square brush")
        case .circle: Text("Round brush")
        case .line: Text("Line brush")
        }
    }

    private var brushAngle: some View {
        HStack(spacing: 2) {
            Image(systemName: "angle").font(.system(size: 13, weight: .medium)).accessibilityHidden(true)
            Button { document.brushAngle = (document.brushAngle + 165) % 180 } label: {
                Image(systemName: "minus").frame(width: 30, height: 34)
            }
            .accessibilityLabel(Text("Rotate the brush left"))
            Text(verbatim: "\(document.brushAngle)°")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(width: 40)
                .accessibilityLabel(Text("Brush angle: \(document.brushAngle) degrees"))
            Button { document.brushAngle = (document.brushAngle + 15) % 180 } label: {
                Image(systemName: "plus").frame(width: 30, height: 34)
            }
            .accessibilityLabel(Text("Rotate the brush right"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
    }

    private func stepper(value: Binding<Int>, range: ClosedRange<Int>, label: LocalizedStringKey, unit: String?) -> some View {
        HStack(spacing: 2) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).fixedSize()
            Button { value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1) } label: {
                Image(systemName: "minus").frame(width: 30, height: 34)
            }
            .disabled(value.wrappedValue <= range.lowerBound)
            .accessibilityLabel(Text("Less"))
            Text(verbatim: unit.map { "\(value.wrappedValue) \($0)" } ?? "\(value.wrappedValue)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .frame(minWidth: 34)
            Button { value.wrappedValue = min(range.upperBound, value.wrappedValue + 1) } label: {
                Image(systemName: "plus").frame(width: 30, height: 34)
            }
            .disabled(value.wrappedValue >= range.upperBound)
            .accessibilityLabel(Text("More"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.text)
    }

    /// An on/off option as a pill: the whole label is the touch target, and
    /// it fills with the accent color when on.
    private func toggle(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isOn.wrappedValue ? Theme.accent : Theme.muted)
                Text(title).foregroundStyle(isOn.wrappedValue ? Theme.accentText : Theme.text)
            }
            .font(.system(size: 13, weight: .medium))
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(isOn.wrappedValue ? Theme.accentSoft : Theme.chip, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }
}
