import SwiftUI

/// The active tool's options, centered in the editor's top bar over the
/// canvas. As wide as its options, at most the canvas's width; past that it
/// scrolls sideways.
struct ToolOptionsBar: View {
    @Bindable var document: SpriteDocument

    var body: some View {
        ViewThatFits(in: .horizontal) {
            items.padding(.horizontal, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                items.padding(.horizontal, 10)
            }
        }
        .frame(height: 44)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 12))
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

            if document.activeLayer?.isTilemap == true, [.pencil, .eraser, .bucket, .eyedropper].contains(document.tool) {
                divider
                // Tilemaps: draw pixels or place whole tiles.
                Picker("Draw", selection: $document.tileDrawMode) {
                    Image(systemName: "pencil").tag(TileDrawMode.pixels).accessibilityLabel(Text("Pixels"))
                    Image(systemName: "square.grid.2x2").tag(TileDrawMode.tiles).accessibilityLabel(Text("Tiles"))
                }
                .pickerStyle(.segmented)
                .frame(width: 96)
            }

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
                stepper(value: $document.sprayWidth, range: 1...32, label: "Width", unit: "px", presets: [2, 4, 6, 8, 12, 16, 24, 32])
                stepper(value: $document.spraySpeed, range: 1...32, label: "Speed", unit: nil, presets: [1, 2, 4, 8, 16, 32])
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
                toggle("Stop at grid", isOn: $document.fillStopsAtGrid)
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
            if document.tool == .slice {
                divider
                SliceOptions(document: document)
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
                    ForEach(GradientDither.builtIn + ExtensionStore.shared.ditheringMatrices) { Text($0.title).tag($0) }
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
        NumberChip(title: "Corner radius", systemImage: "button.roundedtop.horizontal", value: $document.cornerRadius,
                   range: 0...SpriteDocument.maxCornerRadius, unit: "px", presets: [0, 1, 2, 3, 4, 6, 8, 12, 16, 32])
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
        NumberChip(title: "Tolerance", value: value, range: 0...255, presets: [0, 8, 16, 32, 48, 64, 96, 128, 192, 255])
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
            textSize
            toggle("Outline", isOn: $document.textStyle.outline)
            Text("Tap the canvas to write")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize()
        }
    }

    /// Pixel fonts grow in whole-pixel scales; system fonts in points.
    @ViewBuilder
    private var textSize: some View {
        if case .pixel = document.textStyle.font {
            NumberChip(title: "Text size", systemImage: "textformat.size", value: $document.textStyle.scale,
                       range: 1...8, unit: "×", presets: [1, 2, 3, 4, 5, 6, 7, 8])
        } else {
            NumberChip(title: "Text size", systemImage: "textformat.size", value: $document.textStyle.pointSize,
                       range: 6...128, step: 2, unit: "pt", presets: [8, 10, 12, 16, 20, 24, 32, 48, 64, 96])
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.border).frame(width: 1, height: 22)
    }

    private var brushSize: some View {
        NumberChip(title: "Brush size", systemImage: "circle.fill", value: Binding(get: { document.brushSize }, set: { document.setBrushSize($0) }),
                   range: 1...SpriteDocument.maxBrushSize, unit: "px", presets: [1, 2, 3, 4, 6, 8, 12, 16, 24, 32])
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
        NumberChip(title: "Brush angle", systemImage: "angle", value: $document.brushAngle,
                   range: 0...179, step: 15, unit: "°", presets: [0, 15, 30, 45, 60, 90, 120, 135, 150, 165])
    }

    private func stepper(value: Binding<Int>, range: ClosedRange<Int>, label: LocalizedStringKey, unit: String?, presets: [Int]) -> some View {
        NumberChip(title: label, value: value, range: range, unit: unit ?? "", presets: presets)
    }

    private func toggle(_ title: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        PillToggle(title: title, isOn: isOn)
    }
}
