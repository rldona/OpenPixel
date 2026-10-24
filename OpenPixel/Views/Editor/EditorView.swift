import SwiftUI

struct EditorView: View {
    @Bindable var document: SpriteDocument
    @Environment(DocumentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var canvas = CanvasController()
    @State private var zoom: CGFloat = 1
    @State private var showingExport = false
    @State private var showingRename = false
    @State private var showingGridSettings = false
    @State private var renameText = ""
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
    /// Dragging this far below the smallest size collapses the timeline.
    private static let collapsePull = 50.0

    var body: some View {
        let sprite = document.sprite

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
                        ZStack(alignment: .bottomLeading) {
                            PixelCanvas(
                                document: document,
                                controller: canvas,
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
                                onZoomChanged: { zoom = $0 },
                                onFocusToggle: toggleFocus
                            )
                            if !focusMode && !timelineCollapsed && !document.hasSelection && !document.isTransforming { statusPills }
                        }
                        .overlay(alignment: .topLeading) {
                            if !focusMode { ToolOptionsBar(document: document).padding(14) }
                        }
                        .overlay(alignment: .topTrailing) {
                            if focusMode { focusExitButton }
                        }
                        .overlay(alignment: .bottom) {
                            VStack(spacing: 0) {
                                if document.isTransforming {
                                    TransformBar(document: document).padding(14)
                                } else if document.hasSelection {
                                    SelectionActionBar(document: document).padding(14)
                                }
                                if !focusMode && timelineCollapsed {
                                    TimelineCapsule(document: document, expand: expandTimeline)
                                        .padding(.bottom, 14)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                        }
                        .overlay(alignment: .top) { noticeBanner.padding(.top, 58) }
                    }
                    if !focusMode && !timelineCollapsed {
                        FrameTimeline(document: document)
                            .frame(height: CGFloat(timelineHeight))
                            // The grab bar floats over the timeline's top edge, taking no room from the canvas.
                            .overlay(alignment: .top) { timelineResizeHandle.offset(y: -18) }
                        // While pulled past its smallest size it slides down and fades, to show it's about to hide.
                        .offset(y: timelinePull)
                        .opacity(1 - 0.5 * min(1, timelinePull / Self.collapsePull))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                if !focusMode {
                    SidePanel(document: document)
                        .frame(width: 280)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .background {
            Button("Focus mode", action: toggleFocus)
                .keyboardShortcut(.tab, modifiers: [])
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
        .alert("Rename project", isPresented: $showingRename) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { document.name = trimmed }
            }
        }
        .onChange(of: document.revision) { scheduleSave() }
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
                .frame(width: 44, height: 44)
                .background(Theme.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
        .padding(14)
        .accessibilityLabel(Text("Exit focus mode"))
        .transition(.opacity)
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
            .fill(timelineDragStart != nil ? Theme.accent : Theme.strongBorder)
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
                let fit = Double(FrameTimeline.fittingHeight(for: document.sprite))
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

    private func expandTimeline() {
        withAnimation(.easeOut(duration: 0.25)) { timelineCollapsed = false }
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            IconButton(systemImage: "chevron.left", label: "Back to projects") { dismiss() }
            Button {
                renameText = document.name
                showingRename = true
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(document.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    (Text(verbatim: "\(document.sprite.width) × \(document.sprite.height) · RGBA · ")
                        + (document.sprite.frames.count == 1 ? Text("1 frame") : Text("\(document.sprite.frames.count) frames"))
                        + Text(verbatim: " · ")
                        + (document.sprite.layers.count == 1 ? Text("1 layer") : Text("\(document.sprite.layers.count) layers")))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)

            IconButton(systemImage: "arrow.uturn.backward", label: "Undo") { document.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .opacity(document.canUndo || document.isTransforming ? 1 : 0.35)
            IconButton(systemImage: "arrow.uturn.forward", label: "Redo") { document.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .opacity(document.canRedo ? 1 : 0.35)

            Spacer()

            EditMenu(document: document)
            IconButton(systemImage: "arrow.up.left.and.arrow.down.right", label: "Focus mode", action: toggleFocus)
            gridMenu
            tiledModeMenu
            HStack(spacing: 0) {
                IconButton(systemImage: "minus", label: "Zoom out", size: 40) { canvas.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button { canvas.fit() } label: {
                    Text(verbatim: "\(Int(zoom * 100))%")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .frame(width: 64, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Fit to screen"))
                .keyboardShortcut("0", modifiers: .command)
                IconButton(systemImage: "plus", label: "Zoom in", size: 40) { canvas.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
            }
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
            .padding(.horizontal, 6)

            Button { showingExport = true } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("e", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    /// Tap toggles the pixel grid; touch and hold for the sprite's grid, snapping and its settings.
    private var gridMenu: some View {
        let isOn = document.showGrid || document.showTileGrid
        return Menu {
            Toggle(isOn: $document.showGrid) { Label("Pixel grid", systemImage: "grid") }
            Toggle(isOn: $document.showTileGrid) { Label("Grid", systemImage: "square.grid.3x3") }
            Toggle(isOn: $document.snapToGrid) { Label("Snap to grid", systemImage: "squareshape.split.3x3") }
            Divider()
            Button("Grid settings…", systemImage: "slider.horizontal.3") { showingGridSettings = true }
        } label: {
            Image(systemName: "grid")
                .font(.system(size: 17.6, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(isOn ? Theme.onAccent : Theme.text)
                .background(isOn ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 11))
        } primaryAction: {
            document.showGrid.toggle()
        }
        .menuIndicator(.hidden)
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
            Picker("Tiled mode", selection: $document.tiledMode) {
                Text("None").tag(TiledMode.none)
                Text("Tile horizontally").tag(TiledMode.horizontal)
                Text("Tile vertically").tag(TiledMode.vertical)
                Text("Tile in both directions").tag(TiledMode.both)
            }
        } label: {
            Image(systemName: "square.grid.3x3.square")
                .font(.system(size: 17.6, weight: .medium))
                .frame(width: 44, height: 44)
                .foregroundStyle(isOn ? Theme.onAccent : Theme.text)
                .background(isOn ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 11))
        }
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("Tiled mode"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var statusPills: some View {
        HStack(spacing: 8) {
            (Text(document.tool.title)
                + Text(verbatim: document.tool.usesBrush ? " \(document.brushSize) px" : "")
                + (document.symmetry.isOn ? Text(" + symmetry") : Text(verbatim: ""))
                + Text(verbatim: " · \(document.activeLayer?.name ?? "") · ")
                + Text("frame \(document.activeFrameIndex + 1)/\(document.sprite.frames.count)")
                + Text(verbatim: document.activeTag.map { " · \($0.name)" } ?? ""))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        }
        .padding(14)
        .allowsHitTesting(false)
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
        }
        .padding(.vertical, 12)
        .frame(width: 68)
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
