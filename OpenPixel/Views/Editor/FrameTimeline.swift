import SwiftUI

/// Aseprite-style timeline: a row of tags, one row per layer, one column per
/// frame, and a dot in each cel (filled when it has pixels, hollow when empty).
struct FrameTimeline: View {
    @Bindable var document: SpriteDocument
    @State private var renaming: Layer?
    @State private var renameText = ""
    @State private var editingTag: FrameTag?

    private let nameColumn: CGFloat = 230
    private let celWidth: CGFloat = 38
    private let rowHeight: CGFloat = 36
    private let headerHeight: CGFloat = 28
    private let tagLaneHeight: CGFloat = 24
    private static let durationPresets = [50, 80, 100, 120, 150, 200, 250, 300, 500, 1000]
    private static let speeds: [Double] = [0.25, 0.5, 1, 1.5, 2, 3]

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
        .background(Theme.panel.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        .alert("Renombrar capa", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nombre", text: $renameText)
            Button("Cancelar", role: .cancel) {}
            Button("Guardar") { if let layer = renaming { document.renameLayer(layer.id, to: renameText) } }
        }
        .sheet(item: $editingTag) { tag in
            TagEditor(
                tag: tag,
                frameCount: document.sprite.frames.count,
                onSave: { document.updateTag($0) },
                onDelete: { document.deleteTag(tag.id) }
            )
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
            Menu {
                Picker("Velocidad", selection: $document.playbackSpeed) {
                    ForEach(Self.speeds, id: \.self) { Text(Self.speedLabel($0)).tag($0) }
                }
            } label: {
                Text(verbatim: Self.speedLabel(document.playbackSpeed))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(document.playbackSpeed == 1 ? Theme.muted : Theme.accent)
                    .frame(width: 44, height: 36)
            }
            .accessibilityLabel("Velocidad de reproducción")

            Rectangle().fill(Theme.border).frame(width: 1, height: 24).padding(.horizontal, 6)

            // Tap duplicates the active frame (Aseprite's New Frame); long press offers an empty one.
            Menu {
                Button("Duplicar frame actual", systemImage: "plus.square.on.square") { document.addFrame() }
                Button("Frame vacío", systemImage: "square.dashed") { document.addFrame(empty: true) }
            } label: {
                pill("Frame", systemImage: "plus", isOn: false)
            } primaryAction: {
                document.addFrame()
            }
            .menuIndicator(.hidden)
            .accessibilityHint("Mantén pulsado para crear un frame vacío")
            .background {
                // Aseprite shortcuts: ⌥N new frame, ⌥⇧N new empty frame.
                Group {
                    Button("Nuevo frame") { document.addFrame() }
                        .keyboardShortcut("n", modifiers: .option)
                    Button("Nuevo frame vacío") { document.addFrame(empty: true) }
                        .keyboardShortcut("n", modifiers: [.option, .shift])
                }
                .opacity(0)
                .accessibilityHidden(true)
            }
            IconButton(systemImage: "trash", label: "Eliminar frame", size: 36) {
                document.deleteFrame(at: document.activeFrameIndex)
            }
            .opacity(document.sprite.frames.count > 1 ? 1 : 0.35)

            Button { editingTag = document.addTag() } label: {
                pill("Tag", systemImage: "tag", isOn: false)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("t", modifiers: [.command, .option])
            .padding(.leading, 4)

            onionMenu
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
                    Text(verbatim: "\(document.activeFrame.duration) ms")
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

    /// Tap toggles onion skin; long press opens its settings.
    private var onionMenu: some View {
        Menu {
            Picker("Frames anteriores", selection: $document.onionSettings.previous) {
                ForEach(0...3, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Frames siguientes", selection: $document.onionSettings.next) {
                ForEach(0...3, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Opacidad", selection: $document.onionSettings.opacity) {
                ForEach([0.2, 0.35, 0.5, 0.65], id: \.self) { Text("\(Int($0 * 100)) %").tag($0) }
            }
            .pickerStyle(.menu)
            Toggle("Teñir (rojo antes, azul después)", isOn: $document.onionSettings.tint)
            Toggle("Solo dentro del tag", isOn: $document.onionSettings.onlyInTag)
        } label: {
            pill("Onion skin", systemImage: "square.on.square.dashed", isOn: document.onionSkin)
        } primaryAction: {
            document.onionSkin.toggle()
        }
        .menuIndicator(.hidden)
        .accessibilityHint("Mantén pulsado para configurarlo")
    }

    private func pill(_ title: String, systemImage: String, isOn: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isOn ? Color(hex: 0xFFB29E) : Theme.text)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(isOn ? Color(hex: 0x3A2A24) : Color(hex: 0x26262D), in: RoundedRectangle(cornerRadius: 9))
    }

    private static func speedLabel(_ speed: Double) -> String {
        speed == speed.rounded() ? "\(Int(speed))×" : "\(speed.formatted(.number.precision(.fractionLength(0...2))))×"
    }

    private func changeDuration(by delta: Int) {
        document.setDuration(document.activeFrame.duration + delta, frameIndex: document.activeFrameIndex)
    }

    // MARK: Layers

    private var layerColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                SectionLabel("Tags")
                Spacer()
                IconButton(systemImage: "plus", label: "Nuevo tag", size: 28) { editingTag = document.addTag() }
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: tagRowHeight)

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
                    .draggable("layer:\(layer.id.uuidString)")
                    .dropDestination(for: String.self) { items, _ in
                        guard let id = items.first.flatMap(Self.layerID) else { return false }
                        document.moveLayer(id, to: layer.id)
                        return true
                    }
            }
        }
        .frame(width: nameColumn)
    }

    private static func layerID(_ payload: String) -> UUID? {
        guard payload.hasPrefix("layer:") else { return nil }
        return UUID(uuidString: String(payload.dropFirst(6)))
    }

    private static func frameIndex(_ payload: String) -> Int? {
        guard payload.hasPrefix("frame:") else { return nil }
        return Int(payload.dropFirst(6))
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
        .background(isActive ? Color(hex: 0x222229) : Theme.panel)
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

    // MARK: Tags

    /// Tags stacked in lanes so overlapping ranges don't cover each other.
    private var tagLanes: [(tag: FrameTag, lane: Int)] {
        var laneEnds: [Int] = []
        return document.sprite.tags.sorted { ($0.from, $0.to) < ($1.from, $1.to) }.map { tag in
            if let lane = laneEnds.firstIndex(where: { $0 < tag.from }) {
                laneEnds[lane] = tag.to
                return (tag, lane)
            }
            laneEnds.append(tag.to)
            return (tag, laneEnds.count - 1)
        }
    }

    private var tagRowHeight: CGFloat {
        CGFloat(max(1, (tagLanes.map(\.lane).max() ?? 0) + 1)) * tagLaneHeight + 4
    }

    private var tagRow: some View {
        let frames = document.sprite.frames.count
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(tagLanes, id: \.tag.id) { item in
                tagBar(item.tag)
                    .offset(x: CGFloat(item.tag.from) * celWidth + 2, y: CGFloat(item.lane) * tagLaneHeight + 2)
            }
        }
        .frame(width: CGFloat(frames) * celWidth, height: tagRowHeight, alignment: .topLeading)
    }

    private func tagBar(_ tag: FrameTag) -> some View {
        let light = Int(tag.color.r) * 3 + Int(tag.color.g) * 6 + Int(tag.color.b) > 1400
        return Button { editingTag = tag } label: {
            HStack(spacing: 4) {
                Image(systemName: tag.direction.systemImage).font(.system(size: 9, weight: .bold))
                Text(tag.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                if tag.repeatCount > 0 {
                    Text(verbatim: "×\(tag.repeatCount)").font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(light ? Theme.onAccent : .white)
            .padding(.horizontal, 6)
            .frame(width: CGFloat(tag.frameCount) * celWidth - 4, height: tagLaneHeight - 4, alignment: .leading)
            .background(tag.color.color, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tag \(tag.name), frames \(tag.from + 1) a \(tag.to + 1), \(tag.direction.title)")
        .contextMenu {
            Button("Editar tag", systemImage: "pencil") { editingTag = tag }
            Button("Reproducir tag", systemImage: "play") {
                document.goToFrame(tag.from)
                document.startPlayback()
            }
            Divider()
            Button("Eliminar tag", systemImage: "trash", role: .destructive) { document.deleteTag(tag.id) }
        }
    }

    // MARK: Cels

    private var celGrid: some View {
        let frames = document.sprite.frames
        let activeTag = document.activeTag
        return VStack(alignment: .leading, spacing: 0) {
            tagRow
            HStack(spacing: 0) {
                ForEach(frames.indices, id: \.self) { index in
                    frameHeader(index, count: frames.count, inActiveTag: activeTag?.contains(index) ?? false)
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

    private func frameHeader(_ index: Int, count: Int, inActiveTag: Bool) -> some View {
        let isActive = index == document.activeFrameIndex
        return Button { document.goToFrame(index) } label: {
            Text(verbatim: "\(index + 1)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(isActive ? Color(hex: 0xFF8A6B) : (inActiveTag ? Theme.text : Theme.muted))
                .frame(width: celWidth, height: headerHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable("frame:\(index)") {
            Text(verbatim: "\(index + 1)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .frame(width: celWidth, height: headerHeight)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(Theme.onAccent)
        }
        .dropDestination(for: String.self) { items, _ in
            guard let source = items.first.flatMap(Self.frameIndex) else { return false }
            document.moveFrame(from: source, to: index)
            return true
        }
        .contextMenu {
            Button("Duplicar frame", systemImage: "plus.square.on.square") {
                document.goToFrame(index)
                document.addFrame()
            }
            Button("Frame vacío después", systemImage: "square.dashed") {
                document.goToFrame(index)
                document.addFrame(empty: true)
            }
            Button("Nuevo tag aquí", systemImage: "tag") {
                document.goToFrame(index)
                editingTag = document.addTag()
            }
            Divider()
            Button("Mover a la izquierda", systemImage: "arrow.left") { document.moveFrame(at: index, by: -1) }
                .disabled(index == 0)
            Button("Mover a la derecha", systemImage: "arrow.right") { document.moveFrame(at: index, by: 1) }
                .disabled(index == count - 1)
            Divider()
            Button("Eliminar frame", systemImage: "trash", role: .destructive) { document.deleteFrame(at: index) }
                .disabled(count <= 1)
        }
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

/// Edits a tag's name, color, frame range, direction and repeat count.
struct TagEditor: View {
    @State var tag: FrameTag
    let frameCount: Int
    let onSave: (FrameTag) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nombre", text: $tag.name)
                    HStack(spacing: 10) {
                        ForEach(FrameTag.colors, id: \.self) { color in
                            Button { tag.color = color } label: {
                                Circle()
                                    .fill(color.color)
                                    .frame(width: 30, height: 30)
                                    .overlay(Circle().strokeBorder(Theme.text, lineWidth: tag.color == color ? 3 : 0))
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Color \(color.hex)")
                        }
                    }
                }
                Section("Frames") {
                    Stepper(value: Binding(get: { tag.from + 1 }, set: { tag.from = $0 - 1; tag.to = max(tag.to, tag.from) }), in: 1...frameCount) {
                        LabeledContent("Desde", value: "\(tag.from + 1)")
                    }
                    Stepper(value: Binding(get: { tag.to + 1 }, set: { tag.to = $0 - 1; tag.from = min(tag.from, tag.to) }), in: 1...frameCount) {
                        LabeledContent("Hasta", value: "\(tag.to + 1)")
                    }
                }
                Section("Reproducción") {
                    Picker("Dirección", selection: $tag.direction) {
                        ForEach(AnimationDirection.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                    Stepper(value: $tag.repeatCount, in: 0...99) {
                        LabeledContent("Repeticiones", value: tag.repeatCount == 0 ? "Infinitas" : "\(tag.repeatCount)")
                    }
                }
                Section {
                    Button("Eliminar tag", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(tag)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
