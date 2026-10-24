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
    @State private var renameText = ""
    @State private var saveTask: Task<Void, Never>?
    /// Focus mode hides everything but the canvas (four-finger tap or Tab).
    @State private var focusMode = false

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
                                spriteSize: CGSize(width: sprite.width, height: sprite.height),
                                showGrid: document.showGrid,
                                mirrorX: document.mirrorX,
                                onZoomChanged: { zoom = $0 },
                                onFocusToggle: toggleFocus
                            )
                            if !focusMode && !document.hasSelection && !document.isTransforming { statusPills }
                        }
                        .overlay(alignment: .topLeading) {
                            if !focusMode { ToolOptionsBar(document: document).padding(14) }
                        }
                        .overlay(alignment: .topTrailing) {
                            if focusMode { focusExitButton }
                        }
                        .overlay(alignment: .bottom) {
                            if document.isTransforming {
                                TransformBar(document: document).padding(14)
                            } else if document.hasSelection {
                                SelectionActionBar(document: document).padding(14)
                            }
                        }
                        .overlay(alignment: .top) { noticeBanner.padding(.top, 58) }
                    }
                    if !focusMode {
                        FrameTimeline(document: document)
                            .frame(height: 200)
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
            IconButton(systemImage: "grid", label: "Pixel grid", isOn: document.showGrid) { document.showGrid.toggle() }
                .keyboardShortcut("'", modifiers: .command)
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

    private var statusPills: some View {
        HStack(spacing: 8) {
            (Text(document.tool.title)
                + Text(verbatim: document.tool.usesBrush ? " \(document.brushSize) px" : "")
                + (document.mirrorX ? Text(" + symmetry") : Text(verbatim: ""))
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
            IconButton(systemImage: "square.split.2x1", label: "Horizontal symmetry", isOn: document.mirrorX, size: 48) {
                document.mirrorX.toggle()
            }
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
