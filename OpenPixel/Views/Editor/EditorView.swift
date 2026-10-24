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

    var body: some View {
        let sprite = document.sprite
        let composite = sprite.composite(frameIndex: document.activeFrameIndex).makeCGImage()

        VStack(spacing: 0) {
            topBar
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ToolRail(document: document)
                        ZStack(alignment: .bottomLeading) {
                            PixelCanvas(
                                document: document,
                                controller: canvas,
                                image: composite,
                                onionLayers: onionLayers(sprite),
                                spriteSize: CGSize(width: sprite.width, height: sprite.height),
                                showGrid: document.showGrid,
                                mirrorX: document.mirrorX,
                                onZoomChanged: { zoom = $0 }
                            )
                            statusPills
                        }
                        .overlay(alignment: .topLeading) {
                            ToolOptionsBar(document: document).padding(14)
                        }
                        .overlay(alignment: .top) { noticeBanner.padding(.top, 58) }
                    }
                    FrameTimeline(document: document)
                        .frame(height: 200)
                }
                SidePanel(document: document, preview: composite)
                    .frame(width: 280)
            }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showingExport) { ExportView(document: document) }
        .alert("Renombrar sprite", isPresented: $showingRename) {
            TextField("Nombre", text: $renameText)
            Button("Cancelar", role: .cancel) {}
            Button("Guardar") {
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
        try? store.save(document)
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            IconButton(systemImage: "chevron.left", label: "Volver a la galería") { dismiss() }
            Button {
                renameText = document.name
                showingRename = true
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(document.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("\(document.sprite.width) × \(document.sprite.height) · RGBA · \(document.sprite.frames.count) frames · \(document.sprite.layers.count) capas")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)

            IconButton(systemImage: "arrow.uturn.backward", label: "Deshacer") { document.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .opacity(document.canUndo ? 1 : 0.35)
            IconButton(systemImage: "arrow.uturn.forward", label: "Rehacer") { document.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .opacity(document.canRedo ? 1 : 0.35)

            Spacer()

            IconButton(systemImage: "grid", label: "Cuadrícula de píxeles", isOn: document.showGrid) { document.showGrid.toggle() }
                .keyboardShortcut("'", modifiers: .command)
            HStack(spacing: 0) {
                IconButton(systemImage: "minus", label: "Alejar", size: 40) { canvas.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                Button { canvas.fit() } label: {
                    Text(verbatim: "\(Int(zoom * 100))%")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .frame(width: 64, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajustar a pantalla")
                .keyboardShortcut("0", modifiers: .command)
                IconButton(systemImage: "plus", label: "Acercar", size: 40) { canvas.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
            }
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
            .padding(.horizontal, 6)

            Button { showingExport = true } label: {
                Label("Exportar", systemImage: "square.and.arrow.up")
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
            Text(verbatim: "\(document.tool.title)\(document.tool.usesBrush ? " \(document.brushSize) px" : "")\(document.mirrorX ? " + simetría" : "") · \(document.activeLayer?.name ?? "") · frame \(document.activeFrameIndex + 1)/\(document.sprite.frames.count)\(document.activeTag.map { " · \($0.name)" } ?? "")")
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
            Label(notice, systemImage: "lock.fill")
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
            ForEach(Tool.allCases) { tool in
                IconButton(systemImage: tool.systemImage, label: tool.title, isOn: document.tool == tool, size: 48) {
                    document.select(tool)
                }
                .keyboardShortcut(tool.shortcut, modifiers: tool.shortcutModifiers)
            }
            Rectangle().fill(Theme.border).frame(width: 32, height: 1).padding(.vertical, 6)
            IconButton(systemImage: "square.split.2x1", label: "Simetría horizontal", isOn: document.mirrorX, size: 48) {
                document.mirrorX.toggle()
            }
            Spacer()
            Button { document.swapColors() } label: {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 7).fill(document.secondary.color)
                        .frame(width: 26, height: 26)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(hex: 0x3A3A43)))
                        .offset(x: 14, y: 14)
                    RoundedRectangle(cornerRadius: 7).fill(document.primary.color)
                        .frame(width: 26, height: 26)
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(hex: 0x3A3A43)))
                }
                .frame(width: 48, height: 48, alignment: .topLeading)
                .padding(.leading, 6)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("x", modifiers: [])
            .accessibilityLabel("Intercambiar color principal y secundario")
        }
        .padding(.vertical, 12)
        .frame(width: 68)
        .background(Theme.panel)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
    }
}
