import SwiftUI

struct EditorView: View {
    @Bindable var document: SpriteDocument
    @Environment(DocumentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var canvas = CanvasController()
    @State private var showingExport = false
    @State private var showingGridSettings = false
    @State private var saveTask: Task<Void, Never>?
    /// Focus mode hides everything but the canvas (four-finger tap or Tab).
    @State private var focusMode = false
    /// Timeline height, set by dragging its top edge (Aseprite's splitter). Kept between sessions.
    @AppStorage("timelineHeight") private var timelineHeight = 200.0
    @State private var timelineDragStart: Double?
    /// Pushed down past its smallest size, the timeline hides behind a small
    /// capsule with play and the frame number (as in Calco).
    @AppStorage("timelineCollapsed") private var timelineCollapsed = false
    /// How far the timeline has been dragged below its smallest size, to show it giving way.
    @State private var timelinePull = 0.0
    private static let timelineHeights = 120.0...560.0
    /// The tool rail's and side panel's widths; the top bar lines up with them.
    static let railWidth: CGFloat = 68
    static let panelWidth: CGFloat = 280
    /// Dragging this far below the smallest size collapses the timeline.
    private static let collapsePull = 50.0

    var body: some View {
        VStack(spacing: 0) {
            if !focusMode {
                topBar.transition(.move(edge: .top).combined(with: .opacity))
            }
            // Three full-height columns: tools | canvas over timeline | side panel.
            HStack(spacing: 0) {
                if !focusMode {
                    ToolRail(document: document).transition(.move(edge: .leading).combined(with: .opacity))
                }
                VStack(spacing: 0) {
                    Group {
                        ZStack(alignment: .bottomTrailing) {
                            CanvasHost(
                                document: document,
                                controller: canvas,
                                onFocusToggle: toggleFocus,
                                onRevision: scheduleSave
                            )
                            .ignoresSafeArea(.container, edges: focusMode || timelineCollapsed ? .bottom : [])
                            // The canvas shows the Hue/Saturation preview; drawing waits until it's applied.
                            .allowsHitTesting(!document.isAdjustingHueSaturation)
                        }
                        .overlay(alignment: .topTrailing) {
                            if focusMode { focusExitButton }
                            if document.isAdjustingHueSaturation {
                                HueSaturationPanel(document: document)
                                    .padding(16)
                                    .padding(.top, focusMode ? 56 : 0)
                                    .transition(.opacity)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            VStack(spacing: 0) {
                                // With the timeline open, the grab bar sits centered between the bars and the
                                // timeline: its capsule is 11 pt above the timeline, 8 pt clear of it, so the
                                // bars end 8 pt above the capsule.
                                let barBottom: CGFloat = !focusMode && !timelineCollapsed ? 22 : 14
                                if document.isTransforming {
                                    TransformBar(document: document).padding([.horizontal, .top], 14).padding(.bottom, barBottom)
                                } else if document.hasSelection {
                                    SelectionActionBar(document: document).padding([.horizontal, .top], 14).padding(.bottom, barBottom)
                                }
                                // Also in focus mode, so the animation can be played and scrubbed full screen.
                                if focusMode || timelineCollapsed {
                                    TimelineCapsule(document: document, exitsFocusMode: focusMode, expand: focusMode ? toggleFocus : expandTimeline)
                                        .padding(.bottom, 14)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                        }
                        .overlay(alignment: .top) { noticeBanner }
                    }
                    if !focusMode && !timelineCollapsed {
                        FrameTimeline(document: document)
                            .frame(height: CGFloat(timelineHeight))
                            // The grab bar floats over the timeline's top edge, taking no room from the canvas.
                            .overlay(alignment: .top) { timelineResizeHandle.offset(y: -22) }
                        // While pulled past its smallest size it slides down and fades, to show it's about to hide.
                        .offset(y: timelinePull)
                        .opacity(1 - 0.5 * min(1, timelinePull / Self.collapsePull))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                if !focusMode {
                    SidePanel(document: document, canvas: canvas)
                        .frame(width: Self.panelWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .background {
            Group {
                Button("Focus mode", action: toggleFocus)
                    .keyboardShortcut(.tab, modifiers: [])
                Button("Zoom out") { canvas.zoomOut() }.keyboardShortcut("-", modifiers: .command)
                Button("Zoom in") { canvas.zoomIn() }.keyboardShortcut("+", modifiers: .command)
                Button("Fit to screen") { canvas.fit() }.keyboardShortcut("0", modifiers: .command)
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .background(Theme.background)
        .background { EditorShortcuts(document: document) }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingExport) { ExportView(document: document) }
        .sheet(isPresented: $document.isReplacingColor) { ReplaceColorSheet(document: document) }
        .sheet(isPresented: Binding(get: { document.textAnchor != nil }, set: { if !$0 { document.textAnchor = nil } })) {
            TextEntrySheet(document: document)
        }
        .onChange(of: document.name) { scheduleSave() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { save() } }
        .onDisappear {
            document.stopPlayback()
            save()
        }
        .task(id: document.notice) {
            guard document.notice != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            document.notice = nil
        }
    }

    /// Previous frames tinted red and next frames tinted blue, fading with distance.
    /// Farthest first, so the nearest frames end up on top.
    private func toggleFocus() {
        withAnimation(.snappy(duration: 0.25)) { focusMode.toggle() }
    }

    /// The only control left in focus mode, so the mode is never a trap.
    private var focusExitButton: some View {
        Button(action: toggleFocus) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 40, height: 40)
                .background(Theme.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
        .padding(14)
        .accessibilityLabel(Text("Exit focus mode"))
        .transition(.opacity)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private func save() {
        saveTask?.cancel()
        guard document.hasUnsavedChanges else { return }
        store.save(document)
    }

    /// Grab bar on the timeline's top edge: drag to resize, keep pushing down to
    /// hide it behind a capsule, double tap to fit every layer.
    private var timelineResizeHandle: some View {
        Capsule()
            // In the accent color, so it reads as something to grab; solid while dragged.
            .fill(Theme.accent.opacity(timelineDragStart != nil ? 1 : 0.75))
            .frame(width: 56, height: 6)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = timelineDragStart ?? timelineHeight
                        timelineDragStart = start
                        let proposed = start - drag.translation.height
                        timelineHeight = min(max(proposed, Self.timelineHeights.lowerBound), Self.timelineHeights.upperBound)
                        timelinePull = max(0, Self.timelineHeights.lowerBound - proposed)
                    }
                    .onEnded { _ in
                        let start = timelineDragStart ?? timelineHeight
                        timelineDragStart = nil
                        if timelinePull >= Self.collapsePull {
                            // Come back at the height it had before this drag.
                            timelineHeight = min(max(start, Self.timelineHeights.lowerBound), Self.timelineHeights.upperBound)
                            withAnimation(.easeOut(duration: 0.25)) {
                                timelineCollapsed = true
                                timelinePull = 0
                            }
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) { timelinePull = 0 }
                        }
                    }
            )
            .onTapGesture(count: 2) {
                let fit = Double(FrameTimeline.fittingHeight(for: document.structure))
                withAnimation(.easeOut(duration: 0.2)) {
                    timelineHeight = min(max(fit, Self.timelineHeights.lowerBound), Self.timelineHeights.upperBound)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("Timeline height"))
            .accessibilityValue(Text(verbatim: "\(Int(timelineHeight)) pt"))
            .accessibilityHint(Text("Drag to resize, or down to hide it. Double tap to fit every layer."))
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 40.0 : -40.0
                timelineHeight = min(max(timelineHeight + step, Self.timelineHeights.lowerBound), Self.timelineHeights.upperBound)
            }
            .accessibilityAction(named: Text("Hide timeline")) {
                withAnimation(.easeOut(duration: 0.25)) { timelineCollapsed = true }
            }
    }

    /// The capsule's arrow brings the timeline back.
    private func expandTimeline() {
        withAnimation(.easeOut(duration: 0.25)) { timelineCollapsed = false }
    }

    /// Laid out over the three columns below: back over the tool rail, the
    /// active tool's options centered over the canvas, and the view buttons
    /// with Export over the side panel.
    private var topBar: some View {
        HStack(spacing: 0) {
            IconButton(systemImage: "chevron.left", label: "Back to projects") { dismiss() }
                .frame(width: Self.railWidth)

            ToolOptionsBar(document: document)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                EditMenu(document: document).help(Text("Edit"))
                focusMenu
                gridMenu
                tiledModeMenu
                exportButton.padding(.leading, 6)
            }
            .padding(.horizontal, 8)
            .frame(width: Self.panelWidth)
        }
        .frame(height: 56)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    /// "Export" with its label, or just the icon when the label doesn't fit.
    private var exportButton: some View {
        Button { showingExport = true } label: {
            ViewThatFits(in: .horizontal) {
                Label("Export", systemImage: "square.and.arrow.up").labelStyle(TightLabelStyle()).padding(.horizontal, 10)
                Image(systemName: "square.and.arrow.up").frame(width: 40)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(height: 40)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Export"))
        .keyboardShortcut("e", modifiers: [.command, .shift])
    }

    /// An icon in the top bar. On, it takes a soft tint, so solid accent stays for Export.
    private func topBarIcon(_ systemImage: String, isOn: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 17.6, weight: .medium))
            .frame(width: 40, height: 40)
            .foregroundStyle(isOn ? Theme.accent : Theme.text)
            .background(isOn ? Theme.accentSoft : Color.clear, in: RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle())
    }

    /// Tap toggles focus mode; touch and hold names it, like the other view buttons.
    private var focusMenu: some View {
        Menu {
            Button("Focus mode", systemImage: "arrow.up.left.and.arrow.down.right", action: toggleFocus)
        } label: {
            topBarIcon("arrow.up.left.and.arrow.down.right", isOn: false)
        } primaryAction: {
            toggleFocus()
        }
        .menuIndicator(.hidden)
        .help(Text("Focus mode"))
        .accessibilityLabel(Text("Focus mode"))
    }

    /// Tap toggles the pixel grid; touch and hold for the sprite's grid, snapping and its settings.
    private var gridMenu: some View {
        let isOn = document.showGrid || document.showTileGrid
        return Menu {
            Section("Grid") {
                Toggle(isOn: $document.showGrid) { Label("Pixel grid", systemImage: "grid") }
                Toggle(isOn: $document.showTileGrid) { Label("Grid", systemImage: "square.grid.3x3") }
                Toggle(isOn: $document.snapToGrid) { Label("Snap to grid", systemImage: "squareshape.split.3x3") }
            }
            Button("Grid settings…", systemImage: "slider.horizontal.3") { showingGridSettings = true }
        } label: {
            topBarIcon("grid", isOn: isOn)
        } primaryAction: {
            document.showGrid.toggle()
        }
        .menuIndicator(.hidden)
        .help(Text("Pixel grid"))
        .accessibilityLabel(Text("Pixel grid"))
        .accessibilityHint(Text("Touch and hold for the grid and snapping"))
        .popover(isPresented: $showingGridSettings) {
            GridSettingsView(document: document).presentationCompactAdaptation(.popover)
        }
        .background {
            Group {
                Button("Pixel grid") { document.showGrid.toggle() }.keyboardShortcut("'", modifiers: .command)
                Button("Grid") { document.showTileGrid.toggle() }.keyboardShortcut("'", modifiers: [.command, .shift])
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    /// Aseprite's View > Tiled Mode.
    private var tiledModeMenu: some View {
        let isOn = document.tiledMode != .none
        return Menu {
            Section("Tiled mode") {
                Picker("Tiled mode", selection: $document.tiledMode) {
                    Text("None").tag(TiledMode.none)
                    Text("Tile horizontally").tag(TiledMode.horizontal)
                    Text("Tile vertically").tag(TiledMode.vertical)
                    Text("Tile in both directions").tag(TiledMode.both)
                }
            }
        } label: {
            topBarIcon("square.grid.3x3.square", isOn: isOn)
        }
        .menuIndicator(.hidden)
        .help(Text("Tiled mode"))
        .accessibilityLabel(Text("Tiled mode"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder
    private var noticeBanner: some View {
        if let notice = document.notice {
            Label { Text(verbatim: notice) } icon: { Image(systemName: "lock.fill") }
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.raised, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.border))
                .padding(.top, 14)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }
}

struct ToolRail: View {
    @Bindable var document: SpriteDocument

    var body: some View {
        VStack(spacing: 6) {
            ForEach(ToolGroup.allCases) { group in
                toolButton(for: group)
            }
            Rectangle().fill(Theme.border).frame(width: 32, height: 1).padding(.vertical, 6)
            symmetryButton
            Spacer()
            // Undo and redo, at the bottom of the rail.
            IconButton(systemImage: "arrow.uturn.backward", label: "Undo", size: 48) { document.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .opacity(document.canUndo || document.isTransforming ? 1 : 0.35)
            IconButton(systemImage: "arrow.uturn.forward", label: "Redo", size: 48) { document.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .opacity(document.canRedo ? 1 : 0.35)
        }
        .padding(.vertical, 12)
        .frame(width: EditorView.railWidth)
        // Background and divider run under the home indicator, like the side panel.
        .background {
            HStack(spacing: 0) {
                Theme.panel
                Rectangle().fill(Theme.border).frame(width: 1)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .background {
            // Aseprite's single-key tool shortcuts; tools inside groups aren't buttons of their own.
            Group {
                ForEach(Tool.allCases) { tool in
                    Button(tool.title) { document.select(tool) }
                        .keyboardShortcut(tool.shortcut, modifiers: tool.shortcutModifiers)
                }
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    /// Tap turns symmetry on and off; touch and hold picks the axes.
    private var symmetryButton: some View {
        let s = document.symmetry
        let icon = s.horizontal && s.vertical ? "square.split.2x2" : (s.vertical ? "square.split.1x2" : "square.split.2x1")
        return Menu {
            Button { document.symmetry.horizontal.toggle(); document.symmetry.isEnabled = true } label: {
                Label("Horizontal symmetry", systemImage: s.horizontal ? "checkmark" : "square.split.2x1")
            }
            Button { document.symmetry.vertical.toggle(); document.symmetry.isEnabled = true } label: {
                Label("Vertical symmetry", systemImage: s.vertical ? "checkmark" : "square.split.1x2")
            }
            Divider()
            Button { document.centerSymmetryAxes() } label: { Label("Center the axes", systemImage: "align.horizontal.center") }
                .disabled(s.axisX2 == nil && s.axisY2 == nil)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .frame(width: 48, height: 48)
                .foregroundStyle(s.isOn ? Theme.onAccent : Theme.text)
                .background(s.isOn ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrowtriangle.down.fill")
                        .font(.system(size: 6))
                        .rotationEffect(.degrees(-45))
                        .foregroundStyle(s.isOn ? Theme.onAccent : Theme.muted)
                        .padding(5)
                }
        } primaryAction: {
            if !s.horizontal && !s.vertical { document.symmetry.horizontal = true }
            document.symmetry.isEnabled.toggle()
        }
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("Symmetry"))
        .accessibilityHint(Text("Touch and hold to choose the axes"))
        .accessibilityAddTraits(s.isOn ? .isSelected : [])
    }

    /// One slot per group. Groups with several tools show the last one used;
    /// tap selects it, touch and hold lists the others.
    @ViewBuilder
    private func toolButton(for group: ToolGroup) -> some View {
        let tool = document.currentTool(in: group)
        let isOn = ToolGroup.of(document.tool) == group
        if group.tools.count == 1 {
            IconButton(systemImage: tool.systemImage, label: tool.title, isOn: isOn, size: 48) {
                document.select(tool)
            }
        } else {
            Menu {
                ForEach(group.tools) { option in
                    Button { document.select(option) } label: { Label(option.title, systemImage: option.systemImage) }
                }
            } label: {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 48, height: 48)
                    .foregroundStyle(isOn ? Theme.onAccent : Theme.text)
                    .background(isOn ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                    // Corner mark: this slot has more tools.
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 6))
                            .rotationEffect(.degrees(-45))
                            .foregroundStyle(isOn ? Theme.onAccent : Theme.muted)
                            .padding(5)
                    }
            } primaryAction: {
                document.select(tool)
            }
            .menuIndicator(.hidden)
            .accessibilityLabel(Text(tool.title))
            .accessibilityHint(Text("Touch and hold for more tools"))
            .accessibilityAddTraits(isOn ? .isSelected : [])
        }
    }
}

/// The canvas and what it shows. It's the only part of the editor that
/// depends on the pixels (`revision`), so a stroke updates it alone instead
/// of rebuilding the toolbars, the timeline and the side panel.
private struct CanvasHost: View {
    let document: SpriteDocument
    let controller: CanvasController
    let onFocusToggle: () -> Void
    /// Called after every committed change (autosave).
    let onRevision: () -> Void

    var body: some View {
        let sprite = document.sprite
        PixelCanvas(
            document: document,
            controller: controller,
            revision: document.revision,
            frameIndex: document.activeFrameIndex,
            onionLayers: onionLayers(sprite),
            references: referenceOverlays(sprite),
            spriteSize: CGSize(width: sprite.width, height: sprite.height),
            showGrid: document.showGrid,
            // A tilemap shows its tiles' grid; otherwise the sprite grid when it's on.
            tileGrid: document.activeLayer?.tileset.map { GridSettings(width: $0.tileWidth, height: $0.tileHeight) }
                ?? (document.showTileGrid ? sprite.grid : nil),
            symmetry: document.symmetry,
            tiledMode: document.tiledMode,
            pixelRatio: sprite.pixelRatio,
            onFocusToggle: onFocusToggle
        )
        .onChange(of: document.revision) { onRevision() }
    }

    private func onionLayers(_ sprite: Sprite) -> [OnionLayer] {
        guard document.onionSkin, !document.isPlaying else { return [] }
        let settings = document.onionSettings
        let current = document.activeFrameIndex
        let tag = settings.onlyInTag ? sprite.tag(containing: current) : nil
        var offsets: [Int] = []
        let maxDistance = max(settings.previous, settings.next)
        if maxDistance > 0 {
            for d in stride(from: maxDistance, through: 1, by: -1) {
                if d <= settings.previous { offsets.append(-d) }
                if d <= settings.next { offsets.append(d) }
            }
        }
        return offsets.compactMap { offset in
            let index = current + offset
            guard sprite.frames.indices.contains(index), tag?.contains(index) ?? true else { return nil }
            var image = sprite.composite(frameIndex: index)
            if settings.tint { image = image.tinted(offset < 0 ? .onionPrevious : .onionNext) }
            guard let cgImage = image.makeCGImage() else { return nil }
            return OnionLayer(image: cgImage, alpha: settings.opacity / CGFloat(abs(offset)))
        }
    }

    /// Visible reference layers, each over the drawing when no drawn layer is above it.
    private func referenceOverlays(_ sprite: Sprite) -> [ReferenceOverlay] {
        sprite.layers.enumerated().compactMap { index, layer in
            guard sprite.shows(layer), let reference = layer.reference else { return nil }
            let above = !sprite.layers[(index + 1)...].contains { !$0.isReference && !$0.isGroup && sprite.shows($0) }
            return ReferenceOverlay(id: layer.id, data: reference.data, frame: reference.frame, opacity: layer.opacity, above: above)
        }
    }
}

/// Icon and title close together, for buttons in tight spots.
private struct TightLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            configuration.title
        }
    }
}
