import SwiftUI

/// Aseprite-style timeline: rows of tags, one row per layer, one column per
/// frame, and a dot in each cel (filled when it has pixels, hollow when empty).
struct FrameTimeline: View {
    @Bindable var document: SpriteDocument
    @State private var renaming: Layer?
    @State private var renameText = ""
    @State private var editingTag: FrameTag?
    /// Aseprite's "First frame as 0 (or any other number)".
    @AppStorage("timelineFirstFrame") private var firstFrame = 1
    private let clipboard = TimelineClipboard.shared

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
        .background { shortcuts }
        .alert("Rename layer", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { if let layer = renaming { document.renameLayer(layer.id, to: renameText) } }
        }
        .sheet(item: $editingTag) { tag in
            TagEditor(
                tag: tag,
                frameCount: document.sprite.frames.count,
                firstFrame: firstFrame,
                onSave: { document.updateTag($0) },
                onDelete: { document.deleteTag(tag.id) }
            )
        }
    }

    private var layersTopFirst: [Layer] { document.sprite.layers.reversed() }

    /// Aseprite's keys: `,` `.` previous/next frame, ⇧X show/hide the active layer.
    private var shortcuts: some View {
        Group {
            Button("Previous frame") { document.goToFrame(document.activeFrameIndex - 1) }
                .keyboardShortcut(",", modifiers: [])
            Button("Next frame") { document.goToFrame(document.activeFrameIndex + 1) }
                .keyboardShortcut(".", modifiers: [])
            Button("Show or hide layer") { document.toggleVisibility(document.activeLayerID) }
                .keyboardShortcut("x", modifiers: .shift)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        if document.isSelectingRange {
            rangeControls
        } else {
            playbackControls
        }
    }

    /// Shown while selecting: what can be done with the selected block.
    private var rangeControls: some View {
        let range = document.timelineRange
        return HStack(spacing: 2) {
            Group {
                if let range {
                    switch range.kind {
                    case .layers:
                        range.layers.count == 1 ? Text("1 layer") : Text("\(range.layers.count) layers")
                    case .frames:
                        range.frames.count == 1 ? Text("1 frame") : Text("\(range.frames.count) frames")
                    case .cels:
                        (range.frames.count == 1 ? Text("1 frame") : Text("\(range.frames.count) frames"))
                            + Text(verbatim: " × ")
                            + (range.layers.count == 1 ? Text("1 layer") : Text("\(range.layers.count) layers"))
                    }
                } else {
                    Text("Tap cels, frame numbers or layer names")
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
            .padding(.horizontal, 6)

            Spacer(minLength: 4)
            Group {
                rangeButton("Copy", "doc.on.doc") { document.copyRange() }
                rangeButton("Link cels", "link") { document.linkRange() }
                    .disabled(range?.kind == .layers)
                rangeButton("Unlink cels", "personalhotspot.slash") { document.unlinkRange() }
                rangeButton("Clear cels", "eraser") { document.clearRange() }
                Rectangle().fill(Theme.border).frame(width: 1, height: 24).padding(.horizontal, 3)
                if range?.kind == .layers {
                    rangeButton("Duplicate layers", "plus.square.on.square") { document.duplicateRangeLayers() }
                    rangeButton("Delete layers", "trash") { document.deleteRangeLayers() }
                } else {
                    rangeButton("Duplicate frames", "plus.square.on.square") { document.duplicateRangeFrames() }
                    rangeButton("Delete frames", "trash") { document.deleteRangeFrames() }
                }
                rangeMoreMenu
            }
            .disabled(range == nil)
            .opacity(range == nil ? 0.4 : 1)

            dragModePicker
                .padding(.leading, 4)

            Button { document.endRangeSelection() } label: {
                Text("Done")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 10)
        .frame(height: 50)
    }

    /// Frame operations that don't need a button of their own.
    private var rangeMoreMenu: some View {
        Menu {
            Button("Reverse frames", systemImage: "arrow.left.arrow.right") { document.reverseRangeFrames() }
            Button("New tag", systemImage: "tag") { editingTag = document.addTag() }
            Button("Set loop section", systemImage: "repeat") { document.setLoopSection() }
            Menu("Frame duration") {
                ForEach(Self.durationPresets, id: \.self) { ms in
                    Button(String("\(ms) ms")) { document.setRangeDuration(ms) }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 40, height: 36)
                .foregroundStyle(Theme.text)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("More"))
        .disabled(document.timelineRange?.kind == .layers)
    }

    /// Whether dragging the selection moves or copies it (Aseprite copies with Ctrl/Alt held).
    private var dragModePicker: some View {
        HStack(spacing: 0) {
            ForEach([false, true], id: \.self) { copies in
                Button { document.dragCopies = copies } label: {
                    Image(systemName: copies ? "plus.rectangle.on.rectangle" : "arrow.up.and.down.and.arrow.left.and.right")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 36, height: 32)
                        .foregroundStyle(document.dragCopies == copies ? Theme.accentText : Theme.muted)
                        .background(document.dragCopies == copies ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(copies ? Text("Dragging copies") : Text("Dragging moves"))
                .accessibilityAddTraits(document.dragCopies == copies ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Theme.chip, in: RoundedRectangle(cornerRadius: 9))
    }

    private func rangeButton(_ title: LocalizedStringKey, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 38, height: 36)
                .foregroundStyle(Theme.text)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
    }

    private var playbackControls: some View {
        HStack(spacing: 4) {
            IconButton(systemImage: "backward.frame", label: "Previous frame", size: 40) {
                document.goToFrame(document.activeFrameIndex - 1)
            }
            .keyboardShortcut(document.isTransforming ? nil : KeyboardShortcut(.leftArrow, modifiers: []))
            IconButton(systemImage: document.isPlaying ? "pause.fill" : "play.fill", label: "Play or pause", isOn: document.isPlaying, size: 40) {
                document.togglePlayback()
            }
            .keyboardShortcut(document.isTransforming ? nil : KeyboardShortcut(.return, modifiers: []))
            IconButton(systemImage: "forward.frame", label: "Next frame", size: 40) {
                document.goToFrame(document.activeFrameIndex + 1)
            }
            .keyboardShortcut(document.isTransforming ? nil : KeyboardShortcut(.rightArrow, modifiers: []))
            Menu {
                Picker("Speed", selection: $document.playbackSpeed) {
                    ForEach(Self.speeds, id: \.self) { Text(Self.speedLabel($0)).tag($0) }
                }
            } label: {
                Text(verbatim: Self.speedLabel(document.playbackSpeed))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(document.playbackSpeed == 1 ? Theme.muted : Theme.accent)
                    .frame(width: 44, height: 36)
            }
            .accessibilityLabel(Text("Playback speed"))

            Rectangle().fill(Theme.border).frame(width: 1, height: 24).padding(.horizontal, 6)

            // Tap duplicates the active frame (Aseprite's New Frame); long press offers an empty one.
            Menu {
                Button("Duplicate current frame", systemImage: "plus.square.on.square") { document.addFrame() }
                Button("Empty frame", systemImage: "square.dashed") { document.addFrame(empty: true) }
            } label: {
                pill("Frame", systemImage: "plus", isOn: false)
            } primaryAction: {
                document.addFrame()
            }
            .menuIndicator(.hidden)
            .accessibilityHint(Text("Touch and hold to add an empty frame"))
            .background {
                // Aseprite shortcuts: ⌥N new frame, ⌥⇧N new empty frame.
                Group {
                    Button("New frame") { document.addFrame() }
                        .keyboardShortcut("n", modifiers: .option)
                    Button("New empty frame") { document.addFrame(empty: true) }
                        .keyboardShortcut("n", modifiers: [.option, .shift])
                }
                .opacity(0)
                .accessibilityHidden(true)
            }
            IconButton(systemImage: "trash", label: "Delete frame", size: 36) {
                document.deleteFrame(at: document.activeFrameIndex)
            }
            .opacity(document.sprite.frames.count > 1 ? 1 : 0.35)

            Button { document.isSelectingRange = true } label: {
                pill("Select", systemImage: "checkmark.rectangle.stack", isOn: false)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)

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
                    .accessibilityLabel(Text("Frame duration"))
                Button(String("−")) { changeDuration(by: -10) }
                    .frame(width: 34, height: 34)
                    .accessibilityLabel(Text("Shorter duration"))
                Menu {
                    ForEach(Self.durationPresets, id: \.self) { ms in
                        Button(String("\(ms) ms")) { document.setDuration(ms, frameIndex: document.activeFrameIndex) }
                    }
                } label: {
                    Text(verbatim: "\(document.activeFrame.duration) ms")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.text)
                        .frame(width: 70)
                }
                Button(String("+")) { changeDuration(by: 10) }
                    .frame(width: 34, height: 34)
                    .accessibilityLabel(Text("Longer duration"))
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
            Picker("Previous frames", selection: $document.onionSettings.previous) {
                ForEach(0...3, id: \.self) { Text(verbatim: "\($0)").tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Next frames", selection: $document.onionSettings.next) {
                ForEach(0...3, id: \.self) { Text(verbatim: "\($0)").tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Opacity", selection: $document.onionSettings.opacity) {
                ForEach([0.2, 0.35, 0.5, 0.65], id: \.self) { Text(verbatim: "\(Int($0 * 100)) %").tag($0) }
            }
            .pickerStyle(.menu)
            Toggle("Tint (red before, blue after)", isOn: $document.onionSettings.tint)
            Toggle("Only inside the tag", isOn: $document.onionSettings.onlyInTag)
        } label: {
            pill("Onion skin", systemImage: "square.on.square.dashed", isOn: document.onionSkin)
        } primaryAction: {
            document.onionSkin.toggle()
        }
        .menuIndicator(.hidden)
        .accessibilityHint(Text("Touch and hold for settings"))
    }

    private func pill(_ title: LocalizedStringKey, systemImage: String, isOn: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isOn ? Theme.accentText : Theme.text)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(isOn ? Theme.accentSoft : Theme.chip, in: RoundedRectangle(cornerRadius: 9))
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
            tagBandHeaders

            HStack(spacing: 4) {
                SectionLabel("Layers")
                Spacer()
                timelineOptions
                IconButton(systemImage: "plus", label: "New layer", size: 28) { document.addLayer() }
                    .keyboardShortcut("n", modifiers: .shift)
                IconButton(systemImage: "trash", label: "Delete layer", size: 28) { document.deleteLayer(document.activeLayerID) }
                    .opacity(document.sprite.layers.count > 1 ? 1 : 0.35)
            }
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .frame(height: headerHeight)

            ForEach(layersTopFirst) { layer in
                layerRow(layer)
                    .draggable(layerDragPayload(layer)) { dragPreview(Text(verbatim: layer.name)) }
                    .dropDestination(for: String.self) { items, _ in
                        guard let payload = items.first else { return false }
                        if let grabbed = RangePayload(payload) {
                            document.dropRange(from: (grabbed.layer, grabbed.frame), to: (layer.id, grabbed.frame))
                            return true
                        }
                        guard let id = Self.layerID(payload) else { return false }
                        document.moveLayer(id, to: layer.id)
                        return true
                    }
            }
        }
        .frame(width: nameColumn)
    }

    /// Timeline preferences (Aseprite's Configure Timeline button).
    private var timelineOptions: some View {
        Menu {
            Picker("First frame number", selection: $firstFrame) {
                Text(verbatim: "0").tag(0)
                Text(verbatim: "1").tag(1)
            }
            .pickerStyle(.menu)
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(Theme.text)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel(Text("Timeline options"))
    }

    /// While a block of layers is selected its rows drag the block; otherwise a row drags its layer.
    private func layerDragPayload(_ layer: Layer) -> String {
        if let range = document.timelineRange, range.kind == .layers, range.layers.contains(layer.id) {
            return RangePayload(layer: layer.id, frame: document.activeFrameIndex).string
        }
        return "layer:\(layer.id.uuidString)"
    }

    private func dragPreview(_ label: Text) -> some View {
        label
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .padding(.horizontal, 10)
            .frame(minWidth: celWidth, minHeight: headerHeight)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(Theme.onAccent)
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
        let inRange = document.timelineRange.map { $0.kind == .layers && $0.layers.contains(layer.id) } ?? false
        return HStack(spacing: 0) {
            Button { document.toggleVisibility(layer.id) } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    .frame(width: 34, height: 34)
                    .foregroundStyle(layer.isVisible ? Theme.text : Theme.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layer.isVisible ? Text("Hide \(layer.name)") : Text("Show \(layer.name)"))
            Button { document.toggleLock(layer.id) } label: {
                Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 13))
                    .frame(width: 30, height: 34)
                    .foregroundStyle(layer.isLocked ? Theme.accent : Theme.muted.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layer.isLocked ? Text("Unlock \(layer.name)") : Text("Lock \(layer.name)"))
            Button { document.toggleContinuous(layer.id) } label: {
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 34)
                    .foregroundStyle(layer.isContinuous ? Theme.accent : Theme.muted.opacity(0.35))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layer.isContinuous ? Text("\(layer.name) is continuous") : Text("Make \(layer.name) continuous"))
            .accessibilityHint(Text("New frames link this layer's cel instead of copying it"))
            Button {
                if document.isSelectingRange { document.extendRange(layerRow: layer.id) } else { document.activeLayerID = layer.id }
            } label: {
                Text(verbatim: layer.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(layer.isVisible ? Theme.text : Theme.muted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .frame(height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Double tap renames, as double-click does in Aseprite.
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                guard !document.isSelectingRange else { return }
                renameText = layer.name
                renaming = layer
            })
        }
        .padding(.leading, 6)
        .frame(height: rowHeight)
        .background(inRange ? Theme.accentSoft : (isActive && !document.isSelectingRange ? Theme.rowActive : Theme.panel))
        .overlay { if inRange { Rectangle().strokeBorder(Theme.accent, lineWidth: 2) } }
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                renameText = layer.name
                renaming = layer
            }
            Button(layer.isLocked ? LocalizedStringKey("Unlock") : LocalizedStringKey("Lock"), systemImage: "lock") { document.toggleLock(layer.id) }
            Toggle(isOn: Binding(get: { layer.isContinuous }, set: { _ in document.toggleContinuous(layer.id) })) {
                Label("Continuous", systemImage: "link")
            }
            Menu("Opacity") {
                ForEach([100, 75, 50, 25], id: \.self) { pct in
                    Button(String("\(pct) %")) { document.setOpacity(Double(pct) / 100, layer: layer.id) }
                }
            }
            Divider()
            Button("Duplicate layer", systemImage: "plus.square.on.square") { document.duplicateLayer(layer.id) }
            Button("Select layers", systemImage: "checkmark.rectangle.stack") {
                document.isSelectingRange = true
                document.extendRange(layerRow: layer.id)
            }
            if clipboard.hasLayers {
                Button("Paste layers above", systemImage: "doc.on.clipboard") {
                    document.activeLayerID = layer.id
                    document.pasteLayers()
                }
            }
            Divider()
            Button("Move up", systemImage: "arrow.up") { document.moveLayer(layer.id, by: 1) }
            Button("Move down", systemImage: "arrow.down") { document.moveLayer(layer.id, by: -1) }
            Divider()
            Button("Delete layer", systemImage: "trash", role: .destructive) { document.deleteLayer(layer.id) }
                .disabled(document.sprite.layers.count <= 1)
        }
    }

    // MARK: Tags

    /// The focused band, if it still exists.
    private var focusedBand: Int? {
        document.focusedTagBand.flatMap { $0 < document.sprite.tagBandCount ? $0 : nil }
    }

    /// Tag bands on screen: only the focused one when a band is focused.
    private var visibleBands: [Int] {
        if let focusedBand { return [focusedBand] }
        return Array(0..<max(1, document.sprite.tagBandCount))
    }

    private var tagRowHeight: CGFloat { CGFloat(visibleBands.count) * tagLaneHeight + 4 }

    /// The "Tags" label and, next to each band, the button that focuses it.
    private var tagBandHeaders: some View {
        let bandCount = document.sprite.tagBandCount
        return VStack(spacing: 0) {
            ForEach(Array(visibleBands.enumerated()), id: \.element) { row, band in
                HStack(spacing: 4) {
                    if row == 0 { SectionLabel("Tags") }
                    Spacer()
                    if bandCount > 1 || focusedBand != nil {
                        Button {
                            document.focusedTagBand = focusedBand == band ? nil : band
                        } label: {
                            Image(systemName: focusedBand == band ? "scope" : "circle.dashed")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 28, height: tagLaneHeight)
                                .foregroundStyle(focusedBand == band ? Theme.accent : Theme.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(focusedBand == band ? Text("Show every tag band") : Text("Focus tag band \(band + 1)"))
                        .accessibilityHint(Text("Play only the tags of this band"))
                    }
                    if row == 0 {
                        IconButton(systemImage: "plus", label: "New tag", size: 28) { editingTag = document.addTag() }
                    } else {
                        Color.clear.frame(width: 28)
                    }
                }
                .frame(height: tagLaneHeight)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .frame(height: tagRowHeight)
    }

    private var tagRow: some View {
        let frames = document.sprite.frames.count
        let bands = visibleBands
        let shown = document.sprite.tagBands.filter { bands.contains($0.band) }
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(shown, id: \.tag.id) { item in
                tagBar(item.tag, band: item.band)
                    .offset(x: CGFloat(item.tag.from) * celWidth + 2, y: CGFloat(bands.firstIndex(of: item.band) ?? 0) * tagLaneHeight + 2)
            }
        }
        .frame(width: CGFloat(frames) * celWidth, height: tagRowHeight, alignment: .topLeading)
    }

    private func tagBar(_ tag: FrameTag, band: Int) -> some View {
        let light = Int(tag.color.r) * 3 + Int(tag.color.g) * 6 + Int(tag.color.b) > 1400
        return Button { editingTag = tag } label: {
            HStack(spacing: 4) {
                Image(systemName: tag.direction.systemImage).font(.system(size: 9, weight: .bold))
                Text(verbatim: tag.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
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
        .accessibilityLabel(Text("Tag \(tag.name), frames \(tag.from + firstFrame) to \(tag.to + firstFrame)") + Text(verbatim: ", ") + Text(tag.direction.title))
        .contextMenu {
            Button("Edit tag", systemImage: "pencil") { editingTag = tag }
            Button("Play tag", systemImage: "play") {
                document.goToFrame(tag.from)
                document.startPlayback()
            }
            Button(focusedBand == band ? LocalizedStringKey("Show every tag band") : LocalizedStringKey("Focus this band"), systemImage: "scope") {
                document.focusedTagBand = focusedBand == band ? nil : band
            }
            Button("Select frames", systemImage: "checkmark.rectangle.stack") {
                document.isSelectingRange = true
                document.extendRange(frameIndex: tag.from)
                document.extendRange(frameIndex: tag.to)
            }
            Divider()
            Button("Delete tag", systemImage: "trash", role: .destructive) { document.deleteTag(tag.id) }
        }
    }

    // MARK: Cels

    /// While selecting, one extra column past the end takes blocks dragged beyond the last frame.
    private var showsDropColumn: Bool {
        document.isSelectingRange && document.timelineRange.map { $0.kind != .layers } == true
    }

    private var celGrid: some View {
        let frames = document.sprite.frames
        let activeTag = document.activeTag
        return VStack(alignment: .leading, spacing: 0) {
            tagRow
            HStack(spacing: 0) {
                ForEach(frames.indices, id: \.self) { index in
                    frameHeader(index, count: frames.count, inActiveTag: activeTag?.contains(index) ?? false)
                }
                if showsDropColumn {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: celWidth, height: headerHeight)
                        .dropDestination(for: String.self) { items, _ in dropRange(items, layer: nil, frame: frames.count) }
                }
            }
            ForEach(layersTopFirst) { layer in
                HStack(spacing: 0) {
                    ForEach(frames.indices, id: \.self) { index in
                        celButton(layer: layer, frameIndex: index, frame: frames[index])
                    }
                    if showsDropColumn {
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: celWidth - 4, height: 30)
                            .frame(width: celWidth)
                            .contentShape(Rectangle())
                            .dropDestination(for: String.self) { items, _ in dropRange(items, layer: layer.id, frame: frames.count) }
                            .accessibilityLabel(Text("After the last frame"))
                    }
                }
                .frame(height: rowHeight)
                .background(layer.id == document.activeLayerID && !document.isSelectingRange ? Theme.rowActive : .clear)
            }
        }
        .padding(.trailing, 16)
    }

    /// Drops a dragged block on (`layer`, `frame`); a nil layer keeps the block's layers (drops on frame numbers).
    private func dropRange(_ items: [String], layer: UUID?, frame: Int) -> Bool {
        guard let grabbed = items.first.flatMap(RangePayload.init) else { return false }
        document.dropRange(from: (grabbed.layer, grabbed.frame), to: (layer ?? grabbed.layer, frame))
        return true
    }

    private func frameHeader(_ index: Int, count: Int, inActiveTag: Bool) -> some View {
        let isActive = index == document.activeFrameIndex
        let range = document.timelineRange
        let inRange = range.map { $0.kind == .frames && $0.frames.contains(index) } ?? false
        let payload = inRange ? RangePayload(layer: document.sprite.layers.last!.id, frame: index).string : "frame:\(index)"
        return Button {
            if document.isSelectingRange { document.extendRange(frameIndex: index) } else { document.goToFrame(index) }
        } label: {
            Text(verbatim: "\(index + firstFrame)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(inRange || isActive ? Theme.accentText : (inActiveTag ? Theme.text : Theme.muted))
                .frame(width: celWidth, height: headerHeight)
                .background(inRange ? Theme.accentSoft : .clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .draggable(payload) {
            dragPreview(inRange && range!.frames.count > 1
                ? Text(verbatim: "\(range!.frames.lowerBound + firstFrame)–\(range!.frames.upperBound + firstFrame)")
                : Text(verbatim: "\(index + firstFrame)"))
        }
        .dropDestination(for: String.self) { items, _ in
            if dropRange(items, layer: nil, frame: index) { return true }
            guard let source = items.first.flatMap(Self.frameIndex) else { return false }
            document.moveFrame(from: source, to: index)
            return true
        }
        .contextMenu {
            Button("Duplicate frame", systemImage: "plus.square.on.square") {
                document.goToFrame(index)
                document.addFrame()
            }
            Button("Empty frame after", systemImage: "square.dashed") {
                document.goToFrame(index)
                document.addFrame(empty: true)
            }
            Button("New tag here", systemImage: "tag") {
                document.goToFrame(index)
                editingTag = document.addTag()
            }
            Button("Select frames", systemImage: "checkmark.rectangle.stack") {
                document.isSelectingRange = true
                document.extendRange(frameIndex: index)
            }
            if clipboard.hasFrames {
                Button("Paste frames after", systemImage: "doc.on.clipboard") {
                    document.goToFrame(index)
                    document.pasteFrames()
                }
            }
            Divider()
            Button("Move left", systemImage: "arrow.left") { document.moveFrame(at: index, by: -1) }
                .disabled(index == 0)
            Button("Move right", systemImage: "arrow.right") { document.moveFrame(at: index, by: 1) }
                .disabled(index == count - 1)
            Divider()
            Button("Delete frame", systemImage: "trash", role: .destructive) { document.deleteFrame(at: index) }
                .disabled(count <= 1)
        }
    }

    private func celButton(layer: Layer, frameIndex: Int, frame: Frame) -> some View {
        let key = CelKey(layer: layer.id, frame: frame.id)
        let filled = document.sprite.cels[key] != nil
        let opacity = document.sprite.celOpacity[key] ?? 1
        let isActive = layer.id == document.activeLayerID && frameIndex == document.activeFrameIndex
        let isActiveFrame = frameIndex == document.activeFrameIndex
        let inRange = document.timelineRange.map { $0.layers.contains(layer.id) && $0.frames.contains(frameIndex) } ?? false
        let dot = (isActive && !document.isSelectingRange ? Theme.onAccent : Theme.dot).opacity(0.35 + 0.65 * opacity)
        let links = linkNeighbours(layer: layer, frameIndex: frameIndex)
        let background: Color = document.isSelectingRange
            ? (inRange ? Theme.accentSoft : Theme.raised)
            : (isActive ? Theme.accent : (isActiveFrame ? Theme.columnActive : Theme.raised))
        let cel = Button {
            if document.isSelectingRange {
                document.extendRange(layer: layer.id, frameIndex: frameIndex)
            } else {
                document.selectCel(layer: layer.id, frameIndex: frameIndex)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(background)
                    .overlay {
                        if inRange { RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.accent, lineWidth: 2) }
                    }
                // Linked cels are joined by a line, as in Aseprite's timeline.
                HStack(spacing: 0) {
                    Rectangle().fill(links.before ? dot : .clear).frame(height: 2)
                    Color.clear.frame(width: 10)
                    Rectangle().fill(links.after ? dot : .clear).frame(height: 2)
                }
                .padding(.horizontal, -2)
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
        .accessibilityLabel(filled ? Text("Cel \(layer.name), frame \(frameIndex + firstFrame)") : Text("Cel \(layer.name), frame \(frameIndex + firstFrame), empty"))
        .accessibilityValue(document.sprite.isLinked(key) ? Text("Linked") : Text(verbatim: ""))
        .dropDestination(for: String.self) { items, _ in dropRange(items, layer: layer.id, frame: frameIndex) }
        .contextMenu {
            if filled {
                Menu("Cel opacity") {
                    ForEach([100, 75, 50, 25], id: \.self) { pct in
                        Button(String("\(pct) %")) { document.setCelOpacity(Double(pct) / 100, layer: layer.id, frameIndex: frameIndex) }
                    }
                }
            }
            if document.sprite.isLinked(key) {
                Button("Unlink cel", systemImage: "personalhotspot.slash") { document.unlinkCel(layer: layer.id, frameIndex: frameIndex) }
            }
            Button("Select cels", systemImage: "checkmark.rectangle.stack") {
                document.isSelectingRange = true
                document.extendRange(layer: layer.id, frameIndex: frameIndex)
            }
            if clipboard.hasCels {
                Button("Paste cels here", systemImage: "doc.on.clipboard") {
                    document.selectCel(layer: layer.id, frameIndex: frameIndex)
                    document.pasteCels()
                }
            }
        }
        // Selected cels drag the whole block (Aseprite drags it from its border).
        return Group {
            if inRange, document.timelineRange?.kind == .cels {
                cel.draggable(RangePayload(layer: layer.id, frame: frameIndex).string) {
                    dragPreview(document.timelineRange.map { r in
                        Text(verbatim: "\(r.frames.count) × \(r.layers.count)")
                    } ?? Text(verbatim: ""))
                }
            } else {
                cel
            }
        }
    }

    /// Whether this cel is linked with the cel in the previous / next frame of its layer.
    private func linkNeighbours(layer: Layer, frameIndex: Int) -> (before: Bool, after: Bool) {
        let sprite = document.sprite
        func group(_ i: Int) -> UUID? {
            guard sprite.frames.indices.contains(i) else { return nil }
            return sprite.links[CelKey(layer: layer.id, frame: sprite.frames[i].id)]
        }
        guard let g = group(frameIndex) else { return (false, false) }
        return (group(frameIndex - 1) == g, group(frameIndex + 1) == g)
    }
}

/// Drag payload of a selected block: the cel it was grabbed from.
private struct RangePayload {
    var layer: UUID
    var frame: Int

    init(layer: UUID, frame: Int) {
        self.layer = layer
        self.frame = frame
    }

    init?(_ string: String) {
        let parts = string.split(separator: ":")
        guard parts.count == 3, parts[0] == "range", let layer = UUID(uuidString: String(parts[1])), let frame = Int(parts[2]) else { return nil }
        self.init(layer: layer, frame: frame)
    }

    var string: String { "range:\(layer.uuidString):\(frame)" }
}

/// Edits a tag's name, color, frame range, direction and repeat count.
struct TagEditor: View {
    @State var tag: FrameTag
    let frameCount: Int
    var firstFrame = 1
    let onSave: (FrameTag) -> Void
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $tag.name)
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
                            .accessibilityLabel(Text("Color \(color.hex)"))
                        }
                    }
                }
                Section("Frames") {
                    Stepper(value: Binding(get: { tag.from }, set: { tag.from = $0; tag.to = max(tag.to, tag.from) }), in: 0...(frameCount - 1)) {
                        LabeledContent("From", value: "\(tag.from + firstFrame)")
                    }
                    Stepper(value: Binding(get: { tag.to }, set: { tag.to = $0; tag.from = min(tag.from, tag.to) }), in: 0...(frameCount - 1)) {
                        LabeledContent("To", value: "\(tag.to + firstFrame)")
                    }
                }
                Section("Playback") {
                    Picker("Direction", selection: $tag.direction) {
                        ForEach(AnimationDirection.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                    Stepper(value: $tag.repeatCount, in: 0...99) {
                        LabeledContent("Repeat") { tag.repeatCount == 0 ? Text("Forever") : Text(verbatim: "\(tag.repeatCount)") }
                    }
                }
                Section {
                    Button("Delete tag", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(tag)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
