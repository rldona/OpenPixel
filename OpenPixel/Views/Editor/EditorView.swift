import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @Bindable var document: SpriteDocument
    @Environment(DocumentStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var canvas = CanvasController()
    @State private var showingExport = false
    @State private var showingGridSettings = false
    @State private var showingShortcuts = false
    /// The file import in progress, kept once the picker clears the request.
    @State private var lastImport: SpriteDocument.FileImport?
    @State private var saveTask: Task<Void, Never>?
    /// Focus mode hides everything but the canvas (four-finger tap or Tab).
    @State private var focusMode = false
    @State private var renamingSprite = false
    @State private var renameText = ""
    /// Timeline height, set by dragging its top edge (Aseprite's splitter). Kept between sessions.
    /// Four layer rows by default: controls (44), frame numbers (25) and 4 × 30,
    /// less the home indicator's strip, which the timeline runs under.
    /// A new key, so the new default reaches everyone.
    @AppStorage("timelineHeight4") private var timelineHeight = 172.0
    @State private var timelineDragStart: Double?
    /// Pushed down past its smallest size, the timeline hides behind a small
    /// capsule with play and the frame number (as in Calco).
    @AppStorage("timelineCollapsed") private var timelineCollapsed = false
    /// How far the timeline has been dragged below its smallest size, to show it giving way.
    @State private var timelinePull = 0.0
    /// Aseprite's Mirrored Default layout (Preferences > Layout): tools on the right, panel on the left.
    @AppStorage(EditorSettings.mirroredLayoutKey) private var mirrored = false
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
            // Three full-height columns: tools | canvas over timeline | side panel, or the other way round.
            HStack(spacing: 0) {
                if !focusMode {
                    if mirrored { sidePanel } else { toolRail }
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
                            // Focus mode floats in the canvas's corner, clear of the bars centered below.
                            Button(action: toggleFocus) {
                                Image(systemName: focusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.text)
                                    .frame(width: 40, height: 40)
                                    .background(Theme.raised, in: Circle())
                                    .overlay(Circle().strokeBorder(Theme.border))
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(Text("Focus mode"))
                            .accessibilityLabel(Text("Focus mode"))
                            .padding(14)
                            .padding(.bottom, !focusMode && !timelineCollapsed ? 8 : 0)
                        }
                        .overlay(alignment: .bottom) {
                            VStack(spacing: 0) {
                                // With the timeline open, the grab bar sits centered between the bars and the
                                // timeline: its capsule is 11 pt above the timeline, 8 pt clear of it, so the
                                // bars end 8 pt above the capsule.
                                let barBottom: CGFloat = !focusMode && !timelineCollapsed ? 22 : 14
                                // With the timeline open, the selection and transform bars sit in its header.
                                let timelineHidden = focusMode || timelineCollapsed
                                if document.canvasResize != nil {
                                    CanvasResizeBar(document: document).padding([.horizontal, .top], 14).padding(.bottom, barBottom)
                                } else if document.isTransforming && timelineHidden {
                                    TransformBar(document: document).padding([.horizontal, .top], 14).padding(.bottom, barBottom)
                                } else if document.hasSelection && timelineHidden {
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
                    if mirrored { toolRail } else { sidePanel }
                }
            }
            // Floating windows like Aseprite's: they open at the canvas's top right
            // and can be dragged anywhere in the editor, side panel included.
            // Only one is open at a time.
            .overlay {
                GeometryReader { geometry in
                    let inset: CGFloat = focusMode ? 16 : (mirrored ? Self.railWidth : Self.panelWidth) + 16
                    ZStack(alignment: .topTrailing) {
                        // Script dialogs stay open while drawing, as in Aseprite.
                        ForEach(document.scriptDialogs) { dialog in
                            ScriptDialogView(dialog: dialog, area: geometry.size, trailingInset: inset)
                        }
                        if document.isAdjustingHueSaturation {
                            HueSaturationPanel(document: document, area: geometry.size, trailingInset: inset)
                        } else if document.isOutlining {
                            OutlinePanel(document: document, area: geometry.size, trailingInset: inset)
                        } else if document.isShowingColorShading {
                            ColorShadingPanel(document: document, area: geometry.size, trailingInset: inset)
                        }
                    }
                    .transition(.opacity)
                    .padding(.trailing, inset)
                    .padding(.top, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
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
                Button("Actual size") { canvas.actualSize() }.keyboardShortcut("1", modifiers: .command)
                Button("Keyboard shortcuts") { showingShortcuts = true }.keyboardShortcut("/", modifiers: .command)
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
        .background(Theme.background)
        .background { EditorShortcuts(document: document) }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingExport) { ExportView(document: document) }
        .sheet(isPresented: $showingShortcuts) { NavigationStack { KeyboardShortcutsView(showsDone: true) } }
        .sheet(isPresented: $document.isReplacingColor) { ReplaceColorSheet(document: document) }
        .sheet(isPresented: Binding(get: { document.textAnchor != nil }, set: { if !$0 { document.textAnchor = nil } })) {
            TextEntrySheet(document: document)
        }
        .onChange(of: document.name) { scheduleSave() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { save() } }
        .onDisappear {
            document.stopPlayback()
            document.stopScripts()
            save()
            // The gallery shows again before this runs, so it read its cards
            // before this save: bring them up to date once it's written.
            Task { await store.flush() }
        }
        // Scripts picked from Files are added to the Scripts menu and run.
        // The one file picker of the editor (see SpriteDocument.FileImport).
        .fileImporter(
            isPresented: Binding(get: { document.fileImport != nil }, set: { shown in
                if !shown, let kind = document.fileImport { lastImport = kind; document.fileImport = nil }
            }),
            allowedContentTypes: Self.contentTypes(document.fileImport ?? lastImport)
        ) { result in
            guard let kind = document.fileImport ?? lastImport else { return }
            document.fileImport = nil
            importFile(result, as: kind)
        }
        .alert(Text(verbatim: document.scriptMessage?.title ?? ""), isPresented: Binding(get: { document.scriptMessage != nil }, set: { if !$0 { document.scriptMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: document.scriptMessage?.text ?? "")
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
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    private static func contentTypes(_ kind: SpriteDocument.FileImport?) -> [UTType] {
        switch kind {
        case .script: [.luaScript, .plainText]
        case .palette: [.data]
        case .imageLayer, .referenceLayer: [.image]
        case nil: [.data]
        }
    }

    private func importFile(_ result: Result<URL, Error>, as kind: SpriteDocument.FileImport) {
        guard case .success(let url) = result else { return }
        if kind == .script {
            do {
                let script = try ScriptStore.shared.install(contentsOf: url)
                document.runScript(named: script.name, source: try ScriptStore.shared.source(of: script))
            } catch {
                document.scriptMessage = ScriptMessage(title: L10n.string("Couldn't add the script"), text: error.localizedDescription)
            }
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let name = url.deletingPathExtension().lastPathComponent
        switch kind {
        case .palette:
            guard let colors = PaletteFile.colors(from: data, fileExtension: url.pathExtension) else {
                document.notice = L10n.string("Couldn't read a palette from that file")
                return
            }
            // Imported palettes stay in Load preset for every sprite.
            let paletteName = PaletteFile.name(in: data) ?? name
            Palette.save(colors, name: paletteName)
            document.setPalette(colors)
            document.notice = L10n.string("“%@” is now in Load preset", paletteName)
        case .imageLayer: document.importLayer(imageData: data, name: name)
        case .referenceLayer: document.addReferenceLayer(imageData: data, name: name)
        case .script: break
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
    private var toolRail: some View {
        ToolRail(document: document, mirrored: mirrored) { document.fileImport = .script }
            .transition(.move(edge: mirrored ? .trailing : .leading).combined(with: .opacity))
    }

    private var sidePanel: some View {
        SidePanel(document: document, canvas: canvas, mirrored: mirrored)
            .frame(width: Self.panelWidth)
            .transition(.move(edge: mirrored ? .leading : .trailing).combined(with: .opacity))
    }

    private var topBar: some View {
        HStack(spacing: 0) {
            IconButton(systemImage: "chevron.left", label: "Back to projects") { dismiss() }
                .frame(width: Self.railWidth)
            spriteName

            ToolOptionsBar(document: document)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)

            // Undo, redo, zoom, grid and Edit in one capsule, then Export.
            HStack(spacing: 0) {
                Button { document.undo() } label: { topBarIcon("arrow.uturn.backward", isOn: false) }
                    .buttonStyle(.plain)
                    .keyboardShortcut("z", modifiers: .command)
                    .opacity(document.canUndo || document.isTransforming ? 1 : 0.35)
                    .help(Text("Undo"))
                    .accessibilityLabel(Text("Undo"))
                Button { document.redo() } label: { topBarIcon("arrow.uturn.forward", isOn: false) }
                    .buttonStyle(.plain)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .opacity(document.canRedo ? 1 : 0.35)
                    .help(Text("Redo"))
                    .accessibilityLabel(Text("Redo"))
                ZoomMenu(canvas: canvas)
                gridMenu
                EditMenu(document: document, addScript: { document.fileImport = .script }) { showingShortcuts = true }.help(Text("Edit"))
            }
            .padding(.horizontal, 4)
            .frame(height: 44)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
            exportButton
                .padding(.leading, 8)
                .padding(.trailing, 8)
        }
        .frame(height: 56)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    /// The sprite's name beside Back; tap to rename it.
    private var spriteName: some View {
        Button {
            renameText = document.name
            renamingSprite = true
        } label: {
            Text(verbatim: document.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 140, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 2)
        .accessibilityLabel(Text(verbatim: document.name))
        .accessibilityHint(Text("Renames the sprite"))
        .alert("Rename sprite", isPresented: $renamingSprite) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { document.name = name }
            }
        }
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

    /// Tap toggles the pixel grid; touch and hold for the sprite's grid, snapping and its settings.
    private var gridMenu: some View {
        let isOn = document.showGrid || document.showTileGrid || document.tiledMode != .none
        return Menu {
            Section("Grid") {
                Toggle(isOn: $document.showGrid) { Label("Pixel grid", systemImage: "grid") }
                Toggle(isOn: $document.showTileGrid) { Label("Grid", systemImage: "square.grid.3x3") }
                Toggle(isOn: $document.snapToGrid) { Label("Snap to grid", systemImage: "squareshape.split.3x3") }
            }
            // Aseprite's View > Tiled Mode: the sprite repeated around itself.
            Picker(selection: $document.tiledMode) {
                Text("None").tag(TiledMode.none)
                Text("Tile horizontally").tag(TiledMode.horizontal)
                Text("Tile vertically").tag(TiledMode.vertical)
                Text("Tile in both directions").tag(TiledMode.both)
            } label: {
                Label("Tiled mode", systemImage: "square.grid.3x3.square")
            }
            .pickerStyle(.menu)
            if document.tiledMode != .none {
                // The copies tiled mode shows, made part of the drawing.
                Menu {
                    ForEach([2, 3, 4], id: \.self) { n in
                        Button { document.repeatCanvas(copies: n) } label: { Text(verbatim: "× \(n)") }
                    }
                } label: {
                    Label("Make the repetition permanent", systemImage: "square.on.square.dashed")
                }
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

/// The canvas zoom, as a percentage, and what sets it (Aseprite's 100%,
/// Center and Fit Screen). Its own view, so pinching redraws only this.
private struct ZoomMenu: View {
    let canvas: CanvasController

    var body: some View {
        Menu {
            Button("Actual size", systemImage: "1.magnifyingglass") { canvas.actualSize() }
            Button("Center", systemImage: "scope") { canvas.center() }
            Button("Fit to screen", systemImage: "arrow.up.left.and.arrow.down.right.square") { canvas.fit() }
            Divider()
            Button("Zoom in", systemImage: "plus.magnifyingglass") { canvas.zoomIn() }
            Button("Zoom out", systemImage: "minus.magnifyingglass") { canvas.zoomOut() }
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: "\(Int((canvas.zoom * 100).rounded())) %")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .fixedSize()
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("Zoom"))
        .accessibilityValue(Text(verbatim: "\(Int((canvas.zoom * 100).rounded())) %"))
    }
}

/// A vertical slider for the rail, like Procreate's brush size and opacity:
/// a plain track with a pill to drag; while dragging, a card beside the rail
/// names it and shows its value and what it does.
private struct RailSlider: View {
    enum Preview { case size, opacity }
    let label: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let text: (Double) -> String
    let preview: Preview
    var mirrored = false
    /// Called when a drag starts and ends (one undo step per drag).
    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}
    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let thumb: CGFloat = 14
            ZStack(alignment: .top) {
                Capsule().fill(Theme.chip)
                    .overlay(Capsule().strokeBorder(Theme.border))
                Capsule()
                    .fill(Theme.panel)
                    .frame(width: geo.size.width - 6, height: thumb)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .offset(y: 3 + (geo.size.height - thumb - 6) * (1 - fraction))
            }
            .overlay(alignment: .top) {
                if dragging {
                    // Beside the rail, whichever slider it is.
                    let x = geo.frame(in: .named("rail"))
                    card
                        .offset(x: mirrored ? -(x.minX + 8 + 120) : EditorView.railWidth - x.minX + 8)
                        .frame(width: geo.size.width, alignment: .leading)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if !dragging { onBegin() }
                    dragging = true
                    let f = 1 - min(1, max(0, (drag.location.y - thumb / 2) / max(1, geo.size.height - thumb)))
                    value = range.lowerBound + f * (range.upperBound - range.lowerBound)
                }
                .onEnded { _ in
                    dragging = false
                    onEnd()
                })
        }
        .frame(width: 24)
        .accessibilityElement()
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(verbatim: text(value)))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 16
            value = min(range.upperBound, max(range.lowerBound, value + (direction == .increment ? step : -step)))
        }
    }

    /// Just a dot as big (or as opaque) as the brush will paint: the picture says it.
    private var card: some View {
        ZStack {
            switch preview {
            case .size:
                let side = 6 + (value - range.lowerBound) / (range.upperBound - range.lowerBound) * 74
                Rectangle().fill(Theme.text).frame(width: side, height: side)
            case .opacity:
                Circle().fill(Theme.text.opacity(value / range.upperBound)).frame(width: 64, height: 64)
            }
        }
        .frame(width: 96, height: 96)
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
    }
}

struct ToolRail: View {
    @Bindable var document: SpriteDocument
    /// On the right of the canvas, so its divider goes on the left.
    var mirrored = false
    var addScript: () -> Void = {}
    /// Buttons a little under 48 pt, so the size and opacity sliders get room.
    static let button: CGFloat = 44

    var body: some View {
        VStack(spacing: 2) {
            ForEach(ToolGroup.allCases) { group in
                toolButton(for: group)
            }
            Rectangle().fill(Theme.border).frame(width: 32, height: 1).padding(.vertical, 6)
            symmetryButton
            outlineButton
            scriptsButton
            Spacer(minLength: 8)
            // At the end of the rail. With something selected, the selection's opacity;
            // otherwise brush size above opacity, dragged like Procreate's side sliders.
            VStack {
                if document.hasSelection && (document.tool.isSelection || document.tool == .move) && !document.isTransforming {
                    RailSlider(label: "Selection opacity", value: Binding(get: { document.selectionOpacity * 100 }, set: { document.setSelectionOpacity($0 / 100) }),
                               range: 0...100, text: { "\(Int($0.rounded()))%" }, preview: .opacity, mirrored: mirrored,
                               onBegin: { document.beginSelectionOpacity() }, onEnd: { document.endSelectionOpacity() })
                        .frame(maxHeight: 150)
                } else if document.tool.usesBrush || document.tool.usesInk || document.tool == .eraser {
                    // Size above opacity, one after the other like Procreate's.
                    VStack(spacing: 14) {
                        RailSlider(label: "Brush size", value: Binding(get: { Double(document.brushSize) }, set: { document.setBrushSize(Int($0.rounded())) }),
                                   range: 1...Double(SpriteDocument.maxBrushSize), text: { "\(Int($0)) px" }, preview: .size, mirrored: mirrored)
                            .opacity(document.tool.usesBrush && document.activeCustomBrushImage == nil ? 1 : 0.3)
                            .disabled(!document.tool.usesBrush || document.activeCustomBrushImage != nil)
                        RailSlider(label: "Opacity", value: Binding(get: { Double(document.toolOpacity) }, set: { document.toolOpacity = Int($0.rounded()) }),
                                   range: 1...255, text: { "\(Int(($0 / 255 * 100).rounded()))%" }, preview: .opacity, mirrored: mirrored)
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding(.vertical, 12)
        .frame(width: EditorView.railWidth)
        // The sliders place their card beside the rail.
        .coordinateSpace(.named("rail"))
        .zIndex(1)
        // Background and divider run under the home indicator, like the side panel.
        .background {
            HStack(spacing: 0) {
                if mirrored { Rectangle().fill(Theme.border).frame(width: 1) }
                Theme.panel
                if !mirrored { Rectangle().fill(Theme.border).frame(width: 1) }
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

    /// Opens the Outline window (also in the ⋯ menu), and closes it without applying.
    private var outlineButton: some View {
        let isOn = document.isOutlining
        return Button {
            if isOn { document.endOutline(apply: nil, everyCel: false) } else { document.beginOutline() }
        } label: {
            Image(systemName: "smallcircle.filled.circle")
                .font(.system(size: 19, weight: .medium))
                .frame(width: Self.button, height: Self.button)
                .foregroundStyle(isOn ? Theme.onAccent : Theme.text)
                .background(isOn ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Outline"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// Runs a script or an extension's command (also in Edit > Scripts).
    private var scriptsButton: some View {
        Menu {
            ScriptsMenuItems(document: document, addScript: addScript)
        } label: {
            Image(systemName: "curlybraces")
                .font(.system(size: 19, weight: .medium))
                .frame(width: Self.button, height: Self.button)
                .foregroundStyle(Theme.text)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("Scripts"))
    }

    /// Tap turns symmetry on and off; touch and hold picks the axes.
    private var symmetryButton: some View {
        let s = document.symmetry
        // Arrows mirrored across an axis; the corner says which axes are on.
        let icon = s.vertical && !s.horizontal ? "arrow.up.and.line.horizontal.and.arrow.down" : "arrow.left.and.line.vertical.and.arrow.right"
        let axes = s.horizontal && s.vertical ? "HV" : (s.vertical ? "V" : "H")
        return Menu {
            Button { document.symmetry.horizontal.toggle(); document.symmetry.isEnabled = true } label: {
                Label("Horizontal symmetry", systemImage: s.horizontal ? "checkmark" : "arrow.left.and.line.vertical.and.arrow.right")
            }
            Button { document.symmetry.vertical.toggle(); document.symmetry.isEnabled = true } label: {
                Label("Vertical symmetry", systemImage: s.vertical ? "checkmark" : "arrow.up.and.line.horizontal.and.arrow.down")
            }
            Divider()
            Button { document.centerSymmetryAxes() } label: { Label("Center the axes", systemImage: "align.horizontal.center") }
                .disabled(s.axisX2 == nil && s.axisY2 == nil)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .medium))
                .frame(width: Self.button, height: Self.button)
                .foregroundStyle(s.isOn ? Theme.onAccent : Theme.text)
                .background(s.isOn ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                .overlay(alignment: .topLeading) {
                    if s.isOn {
                        Text(verbatim: axes)
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.onAccent.opacity(0.9))
                            .padding(4)
                    }
                }
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

    /// The pencil's menu also makes and picks the custom brush (Edit > New brush).
    @ViewBuilder
    private var customBrushItems: some View {
        Divider()
        if document.customBrush != nil {
            let isOn = document.useCustomBrush && document.tool.usesBrush
            Button {
                if !document.tool.usesBrush { document.select(.pencil) }
                document.useCustomBrush = true
            } label: {
                Label("Custom brush", systemImage: isOn ? "checkmark" : "paintbrush.pointed")
            }
        }
        Button("New brush from selection", systemImage: "paintbrush.pointed.fill") { document.newBrushFromSelection() }
            .disabled(!document.hasSelection)
    }

    /// One slot per group. Groups with several tools show the last one used;
    /// tap selects it, touch and hold lists the others.
    @ViewBuilder
    private func toolButton(for group: ToolGroup) -> some View {
        let tool = document.currentTool(in: group)
        let isOn = ToolGroup.of(document.tool) == group
        if group.tools.count == 1 {
            IconButton(systemImage: tool.systemImage, label: tool.title, isOn: isOn, size: Self.button) {
                document.select(tool)
            }
        } else {
            Menu {
                ForEach(group.tools) { option in
                    Button { document.select(option) } label: { Label(option.title, systemImage: option.systemImage) }
                }
                if group == .pencil { customBrushItems }
            } label: {
                Image(systemName: tool.systemImage)
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: Self.button, height: Self.button)
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
    @AppStorage(EditorSettings.checkerSizeKey) private var checkerSize = 0
    @AppStorage(EditorSettings.checkerLightKey) private var checkerLight = ""
    @AppStorage(EditorSettings.checkerDarkKey) private var checkerDark = ""
    @AppStorage(EditorSettings.pixelGridColorKey) private var pixelGridColor = ""
    @AppStorage(EditorSettings.tileGridColorKey) private var tileGridColor = ""
    @AppStorage(EditorSettings.fingerInputKey) private var fingerInput = FingerInput.automatic
    @AppStorage(EditorSettings.showMeasurementsKey) private var showMeasurements = true
    @AppStorage(EditorSettings.pencilDoubleTapKey) private var pencilDoubleTap = PencilAction.system
    @AppStorage(EditorSettings.pencilSqueezeKey) private var pencilSqueeze = PencilAction.system

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
            // The grid, when it's on: a tilemap's tiles, or the sprite grid.
            tileGrid: document.showTileGrid
                ? (document.activeLayer?.tileset.map { GridSettings(width: $0.tileWidth, height: $0.tileHeight) } ?? sprite.grid)
                : nil,
            symmetry: document.symmetry,
            tiledMode: document.tiledMode,
            pixelRatio: sprite.pixelRatio,
            // The canvas shows the Hue/Saturation preview: it can still be moved and
            // zoomed, but drawing waits until the adjustment is applied or cancelled.
            editingLocked: document.isAdjusting,
            look: CanvasLook(
                checkerSize: checkerSize,
                checkerLight: StoredColor.color(checkerLight),
                checkerDark: StoredColor.color(checkerDark),
                pixelGrid: StoredColor.color(pixelGridColor),
                tileGrid: StoredColor.color(tileGridColor)
            ),
            fingerInput: fingerInput,
            showMeasurements: showMeasurements,
            pencilDoubleTap: pencilDoubleTap,
            pencilSqueeze: pencilSqueeze,
            onFocusToggle: onFocusToggle
        )
        .onChange(of: document.revision) { onRevision() }
    }

    private func onionLayers(_ sprite: Sprite) -> [OnionLayer] {
        guard document.onionSkin, !document.isPlaying else { return [] }
        let settings = document.onionSettings
        let current = document.activeFrameIndex
        var offsets: [Int] = []
        let maxDistance = max(settings.previous, settings.next)
        if maxDistance > 0 {
            for d in stride(from: maxDistance, through: 1, by: -1) {
                if d <= settings.previous { offsets.append(-d) }
                if d <= settings.next { offsets.append(d) }
            }
        }
        // The same frames the timeline marks under their numbers.
        return offsets.compactMap { offset in
            let index = current + offset
            guard document.onionOffset(of: index) != nil else { return nil }
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
