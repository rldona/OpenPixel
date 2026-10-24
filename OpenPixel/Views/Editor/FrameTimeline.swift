import SwiftUI

/// Aseprite-style timeline: one row per layer, one column per frame,
/// and a dot in each cel (filled when it has pixels, hollow when empty).
struct FrameTimeline: View {
    @Bindable var document: SpriteDocument
    @State private var renaming: Layer?
    @State private var renameText = ""

    private let nameColumn: CGFloat = 230
    private let celWidth: CGFloat = 38
    private let rowHeight: CGFloat = 36
    private let headerHeight: CGFloat = 28
    private static let durationPresets = [50, 80, 100, 120, 150, 200, 250, 300, 500, 1000]

    var body: some View {
        VStack(spacing: 0) {
            controls
            Rectangle().fill(Theme.border).frame(height: 1)
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    layerColumn
                    ScrollView(.horizontal, showsIndicators: false) { celGrid }
                }
            }
        }
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        .alert("Renombrar capa", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nombre", text: $renameText)
            Button("Cancelar", role: .cancel) {}
            Button("Guardar") { if let layer = renaming { document.renameLayer(layer.id, to: renameText) } }
        }
    }

    private var layersTopFirst: [Layer] { document.sprite.layers.reversed() }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 4) {
            IconButton(systemImage: "backward.frame", label: "Frame anterior", size: 40) {
                document.goToFrame(document.activeFrameIndex - 1)
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            IconButton(systemImage: document.isPlaying ? "pause.fill" : "play.fill", label: "Reproducir o pausar", isOn: document.isPlaying, size: 40) {
                document.togglePlayback()
            }
            .keyboardShortcut(.return, modifiers: [])
            IconButton(systemImage: "forward.frame", label: "Frame siguiente", size: 40) {
                document.goToFrame(document.activeFrameIndex + 1)
            }
            .keyboardShortcut(.rightArrow, modifiers: [])

            Rectangle().fill(Theme.border).frame(width: 1, height: 24).padding(.horizontal, 6)

            Button { document.addFrame() } label: {
                Label("Frame", systemImage: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(Color(hex: 0x26262D), in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .option)
            IconButton(systemImage: "trash", label: "Eliminar frame", size: 36) {
                document.deleteFrame(at: document.activeFrameIndex)
            }
            .opacity(document.sprite.frames.count > 1 ? 1 : 0.35)

            Button { document.onionSkin.toggle() } label: {
                Label("Onion skin", systemImage: "square.on.square.dashed")
                    .font(.system(size: 13, weight: .medium))
                    .fixedSize()
                    .foregroundStyle(document.onionSkin ? Color(hex: 0xFFB29E) : Theme.text)
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(document.onionSkin ? Color(hex: 0x3A2A24) : Color(hex: 0x26262D), in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)

            Spacer(minLength: 8)

            HStack(spacing: 0) {
                Image(systemName: "timer")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .padding(.leading, 10)
                    .accessibilityLabel("Duración del frame")
                Button("−") { changeDuration(by: -10) }
                    .frame(width: 34, height: 34)
                    .accessibilityLabel("Reducir duración")
                Menu {
                    ForEach(Self.durationPresets, id: \.self) { ms in
                        Button("\(ms) ms") { document.setDuration(ms, frameIndex: document.activeFrameIndex) }
                    }
                } label: {
                    Text("\(document.activeFrame.duration) ms")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .frame(width: 70)
                }
                Button("+") { changeDuration(by: 10) }
                    .frame(width: 34, height: 34)
                    .accessibilityLabel("Aumentar duración")
            }
            .foregroundStyle(Theme.text)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border))
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
    }

    private func changeDuration(by delta: Int) {
        document.setDuration(document.activeFrame.duration + delta, frameIndex: document.activeFrameIndex)
    }

    // MARK: Layers

    private var layerColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                SectionLabel("Capas")
                Spacer()
                IconButton(systemImage: "plus", label: "Nueva capa", size: 28) { document.addLayer() }
                    .keyboardShortcut("n", modifiers: .shift)
                IconButton(systemImage: "trash", label: "Eliminar capa", size: 28) { document.deleteLayer(document.activeLayerID) }
                    .opacity(document.sprite.layers.count > 1 ? 1 : 0.35)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: headerHeight)

            ForEach(layersTopFirst) { layer in
                layerRow(layer)
            }
        }
        .frame(width: nameColumn)
    }

    private func layerRow(_ layer: Layer) -> some View {
        let isActive = layer.id == document.activeLayerID
        return HStack(spacing: 0) {
            Button { document.toggleVisibility(layer.id) } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .frame(width: 34, height: 34)
                    .foregroundStyle(layer.isVisible ? Theme.text : Theme.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layer.isVisible ? "Ocultar \(layer.name)" : "Mostrar \(layer.name)")
            Button { document.toggleLock(layer.id) } label: {
                Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 13))
                    .frame(width: 30, height: 34)
                    .foregroundStyle(layer.isLocked ? Theme.accent : Theme.muted.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layer.isLocked ? "Desbloquear \(layer.name)" : "Bloquear \(layer.name)")
            Button { document.activeLayerID = layer.id } label: {
                Text(layer.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(layer.isVisible ? Theme.text : Theme.muted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .frame(height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 6)
        .frame(height: rowHeight)
        .background(isActive ? Color(hex: 0x222229) : .clear)
        .contextMenu {
            Button("Renombrar", systemImage: "pencil") {
                renameText = layer.name
                renaming = layer
            }
            Button(layer.isLocked ? "Desbloquear" : "Bloquear", systemImage: "lock") { document.toggleLock(layer.id) }
            Menu("Opacidad") {
                ForEach([100, 75, 50, 25], id: \.self) { pct in
                    Button("\(pct) %") { document.setOpacity(Double(pct) / 100, layer: layer.id) }
                }
            }
            Divider()
            Button("Subir", systemImage: "arrow.up") { document.moveLayer(layer.id, by: 1) }
            Button("Bajar", systemImage: "arrow.down") { document.moveLayer(layer.id, by: -1) }
            Divider()
            Button("Eliminar capa", systemImage: "trash", role: .destructive) { document.deleteLayer(layer.id) }
                .disabled(document.sprite.layers.count <= 1)
        }
    }

    // MARK: Cels

    private var celGrid: some View {
        let frames = document.sprite.frames
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(frames.indices, id: \.self) { index in
                    Button { document.goToFrame(index) } label: {
                        Text("\(index + 1)")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(index == document.activeFrameIndex ? Color(hex: 0xFF8A6B) : Theme.muted)
                            .frame(width: celWidth, height: headerHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Duplicar frame", systemImage: "plus.square.on.square") {
                            document.goToFrame(index)
                            document.addFrame()
                        }
                        Button("Frame vacío después", systemImage: "square.dashed") {
                            document.goToFrame(index)
                            document.addFrame(empty: true)
                        }
                        Divider()
                        Button("Mover a la izquierda", systemImage: "arrow.left") { document.moveFrame(at: index, by: -1) }
                            .disabled(index == 0)
                        Button("Mover a la derecha", systemImage: "arrow.right") { document.moveFrame(at: index, by: 1) }
                            .disabled(index == frames.count - 1)
                        Divider()
                        Button("Eliminar frame", systemImage: "trash", role: .destructive) { document.deleteFrame(at: index) }
                            .disabled(frames.count <= 1)
                    }
                }
            }
            ForEach(layersTopFirst) { layer in
                HStack(spacing: 0) {
                    ForEach(frames.indices, id: \.self) { index in
                        celButton(layer: layer, frameIndex: index, frame: frames[index])
                    }
                }
                .frame(height: rowHeight)
                .background(layer.id == document.activeLayerID ? Color(hex: 0x222229) : .clear)
            }
        }
        .padding(.trailing, 16)
    }

    private func celButton(layer: Layer, frameIndex: Int, frame: Frame) -> some View {
        let filled = document.sprite.cel(layer: layer.id, frame: frame.id) != nil
        let isActive = layer.id == document.activeLayerID && frameIndex == document.activeFrameIndex
        let isActiveFrame = frameIndex == document.activeFrameIndex
        let dot = isActive ? Theme.onAccent : Color(hex: 0xD4D4D8)
        return Button { document.selectCel(layer: layer.id, frameIndex: frameIndex) } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isActive ? Theme.accent : (isActiveFrame ? Color(hex: 0x2A2A33) : Theme.raised))
                if filled {
                    Circle().fill(dot).frame(width: 10, height: 10)
                } else {
                    Circle().strokeBorder(dot, lineWidth: 1.5).frame(width: 10, height: 10)
                }
            }
            .frame(width: celWidth - 4, height: 30)
            .frame(width: celWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Cel \(layer.name), frame \(frameIndex + 1)\(filled ? "" : ", vacía")")
    }
}
