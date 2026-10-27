import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Aseprite-style timeline: rows of tags, one row per layer, one column per
/// frame, and a dot in each cel (filled when it has pixels, hollow when empty).
struct FrameTimeline: View {
    @Bindable var document: SpriteDocument
    @State private var renaming: Layer?
    /// Where a layer being dragged in the layer column would land.
    @State private var layerDrop: LayerDropSlot?
    /// Picking the image for a new reference layer.
    @State private var pickingReferencePhoto = false
    @State private var referencePhoto: PhotosPickerItem?
    /// The file picker brings an image or GIF in as a layer of pixels, not a reference.
    @State private var renameText = ""
    @State private var editingTag: FrameTag?
    /// A tag just added from New tag, until its sheet is saved.
    @State private var unsavedTagID: UUID?
    /// Aseprite's "First frame as 0 (or any other number)".
    @AppStorage("timelineFirstFrame") private var firstFrame = 1
    private let clipboard = TimelineClipboard.shared

    private let nameColumn: CGFloat = 294
    /// The check boxes to the left of the eye.
    private let checkColumn: CGFloat = 26
    private let celWidth: CGFloat = 32
    private let rowHeight: CGFloat = 30
    /// Frame numbers grow a second line when some frame's duration differs.
    private var headerHeight: CGFloat { document.structure.usualFrameDuration == nil ? 24 : 34 }
    /// With one band, tags are a slim strip right on top of the frame numbers;
    /// several bands get full lanes, to tell them apart.
    private var tagLaneHeight: CGFloat { document.structure.tagBandCount > 1 ? 20 : 15 }
    private static let durationPresets = [50, 80, 100, 150, 200, 300, 500, 1000, 2000, 4000]
    /// The duration being typed: for the active frame, or for every selected frame.
    @State private var typingDuration: DurationTarget?
    @State private var durationText = ""

    private enum DurationTarget { case activeFrame, range }
    /// Empty frames and layers drawn past the sprite's, so the grid never ends in a gap;
    /// tapping one adds frames or layers up to it.
    private static let projectedFrames = 50
    private static let projectedLayers = 20
    /// How far the cels are scrolled sideways; the header follows it.
    @State private var gridOffset: CGFloat = 0
    private static let speeds: [Double] = [0.25, 0.5, 1, 1.5, 2, 3]
    /// While something is selected the header holds the selection (or transform) bar.
    private var hasEditBar: Bool {
        document.canvasResize == nil && (document.isTransforming || document.hasSelection)
    }

    var body: some View {
        content
            .photosPicker(isPresented: $pickingReferencePhoto, selection: $referencePhoto, matching: .images)
            .onChange(of: referencePhoto) { loadReferencePhoto() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            controls
            Rectangle().fill(Theme.border).frame(height: 1)
            // The header stays put while the layers scroll, and slides sideways with the cels.
            HStack(alignment: .top, spacing: 0) {
                layerHeader
                    .overlay(alignment: .trailing) { Rectangle().fill(Theme.strongBorder).frame(width: 1) }
                // An overlay, so the strip (wider than the screen) takes no room of its own.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: tagRowHeight + headerHeight)
                    .overlay(alignment: .topLeading) { frameHeaderStrip.offset(x: gridOffset) }
                    .clipped()
            }
            .background(Theme.timelineHeader)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.strongBorder).frame(height: 1) }
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    HStack(alignment: .top, spacing: 0) {
                        layerColumn
                            .overlay(alignment: .trailing) { Rectangle().fill(Theme.strongBorder).frame(width: 1) }
                        ScrollView(.horizontal, showsIndicators: false) {
                            celGrid
                                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("cels")).minX } action: { gridOffset = $0 }
                        }
                        .coordinateSpace(.named("cels"))
                    }
                }
                // Keep the layer being worked on in view, also when the timeline
                // comes back (focus mode, reopening the sprite) or the stack changes.
                .onAppear { revealActiveLayer(proxy, animated: false) }
                .onChange(of: document.activeLayerID) { revealActiveLayer(proxy, animated: true) }
                .onChange(of: document.structure.layers.count) { revealActiveLayer(proxy, animated: true) }
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
        .alert("Frame duration", isPresented: Binding(get: { typingDuration != nil }, set: { if !$0 { typingDuration = nil } })) {
            TextField("Milliseconds", text: $durationText)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Save") { saveTypedDuration() }
        } message: {
            Text("In milliseconds: 1000 ms is 1 second.")
        }
        // Cancelling a new tag (or swiping its sheet away) takes it back out, as in Aseprite.
        .sheet(item: $editingTag, onDismiss: {
            if let id = unsavedTagID, document.structure.tags.contains(where: { $0.id == id }) { document.undo() }
            unsavedTagID = nil
        }) { tag in
            TagEditor(
                tag: tag,
                frameCount: document.structure.frames.count,
                firstFrame: firstFrame,
                onSave: {
                    unsavedTagID = nil
                    document.updateTag($0)
                },
                onDelete: { document.deleteTag(tag.id) }
            )
        }
    }

    /// Layers as the timeline lists them: top first, without the ones in collapsed groups.
    private var layersTopFirst: [Layer] {
        let sprite = document.structure
        guard sprite.hasGroups else { return sprite.layers.reversed() }
        return sprite.layers.reversed().filter { layer in sprite.ancestors(of: layer).allSatisfy(\.isExpanded) }
    }

    /// The height that shows every layer without scrolling (controls, tags, frame numbers and rows).
    static func fittingHeight(for sprite: Sprite) -> CGFloat {
        let bands = CGFloat(sprite.tags.isEmpty ? 0 : sprite.tagBandCount)
        let tags = bands > 1 ? bands * 20 + 4 : (bands == 1 ? 16 : 0)
        let header: CGFloat = sprite.usualFrameDuration == nil ? 24 : 34
        return 44 + 1 + tags + header + CGFloat(sprite.layers.count) * 30 + 12
    }

    /// Scrolls just enough to show the active layer's row (nothing if it's visible).
    private func revealActiveLayer(_ proxy: ScrollViewProxy, animated: Bool) {
        let id = document.activeLayerID
        // After layout, so new or returning rows have their place.
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) }
            } else {
                proxy.scrollTo(id)
            }
        }
    }

    private func newTag() {
        let tag = document.addTag()
        unsavedTagID = tag.id
        editingTag = tag
    }

    /// Steps one frame; touch and hold to jump to the first or last one.
    private func stepButton(_ systemImage: String, label: LocalizedStringKey, by step: Int, endLabel: LocalizedStringKey, endImage: String, end: Int) -> some View {
        Menu {
            Button(endLabel, systemImage: endImage) { document.goToFrame(end) }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14.4, weight: .medium))
                .frame(width: 36, height: 36)
                .foregroundStyle(Theme.text)
                .contentShape(Rectangle())
        } primaryAction: {
            document.goToFrame(document.activeFrameIndex + step)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel(Text(label))
        .accessibilityHint(Text("Touch and hold for the first or last frame"))
    }

    /// Aseprite's keys: `,` `.` previous/next frame, ⇧X show/hide the active layer.
    private var shortcuts: some View {
        Group {
            Button("First frame") { document.goToFrame(0) }
                .keyboardShortcut(document.isTransforming ? nil : KeyboardShortcut(.home, modifiers: []))
            Button("Last frame") { document.goToFrame(document.structure.frames.count - 1) }
                .keyboardShortcut(document.isTransforming ? nil : KeyboardShortcut(.end, modifiers: []))
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
        } else if document.isTransforming && hasEditBar {
            TransformBar(document: document, docked: true).padding(.horizontal, 10)
        } else if hasEditBar {
            SelectionActionBar(document: document, docked: true).padding(.horizontal, 10)
        } else {
            // Labels give way to icons when the timeline is narrow.
            ViewThatFits(in: .horizontal) {
                playbackControls(compact: false)
                playbackControls(compact: true)
            }
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
                    rangeButton("Group layers", "folder.badge.plus") {
                        if let ids = range?.layers { document.groupLayers(Array(ids)) }
                        document.isSelectingRange = false
                        document.timelineRange = nil
                    }
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

            // The picked cels stay selected, so edits on the canvas (fill, delete,
            // transforms) keep reaching all of them, as in Aseprite. Tapping a cel clears them.
            Button { document.isSelectingRange = false } label: {
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
        .frame(height: 44)
    }

    /// Frame operations that don't need a button of their own.
    private var rangeMoreMenu: some View {
        Menu {
            Button("Reverse frames", systemImage: "arrow.left.arrow.right") { document.reverseRangeFrames() }
            Button("New tag", systemImage: "tag") { newTag() }
            Button("Set loop section", systemImage: "repeat") { document.setLoopSection() }
            Menu("Frame duration") {
                ForEach(Self.durationPresets, id: \.self) { ms in
                    Button(Self.durationLabel(ms)) { document.setRangeDuration(ms) }
                }
                Divider()
                Button("Custom…", systemImage: "keyboard") { typeDuration(.range) }
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

    private func playbackControls(compact: Bool) -> some View {
        HStack(spacing: 0) {
            // Touch and hold the step buttons to go to the first or last frame.
            stepButton("backward.frame", label: "Previous frame", by: -1, endLabel: "First frame", endImage: "backward.end", end: 0)
                .keyboardShortcut(document.isTransforming ? nil : KeyboardShortcut(.leftArrow, modifiers: []))
            IconButton(systemImage: document.isPlaying ? "pause.fill" : "play.fill", label: "Play or pause", isOn: document.isPlaying, size: 40) {
                document.togglePlayback()
            }
            .keyboardShortcut(document.isTransforming || document.isBuildingShape ? nil : KeyboardShortcut(.return, modifiers: []))
            stepButton("forward.frame", label: "Next frame", by: 1, endLabel: "Last frame", endImage: "forward.end", end: document.structure.frames.count - 1)
                .keyboardShortcut(document.isTransforming ? nil : KeyboardShortcut(.rightArrow, modifiers: []))
            // Where playback is: the frame, of how many.
            Text(verbatim: "\(document.activeFrameIndex + firstFrame) / \(document.structure.frames.count - 1 + firstFrame)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .fixedSize()
                .padding(.horizontal, 6)
                .accessibilityLabel(Text("Frame \(document.activeFrameIndex + firstFrame) of \(document.structure.frames.count)"))
            Menu {
                Picker("Speed", selection: $document.playbackSpeed) {
                    ForEach(Self.speeds, id: \.self) { Text(Self.speedLabel($0)).tag($0) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(verbatim: Self.speedLabel(document.playbackSpeed))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.muted)
                }
                .foregroundStyle(document.playbackSpeed == 1 ? Theme.text : Theme.accent)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(document.playbackSpeed == 1 ? Theme.chip : Theme.accentSoft, in: Capsule())
                .contentShape(Capsule())
            }
            .padding(.leading, 4)
            .accessibilityLabel(Text("Playback speed"))

            Rectangle().fill(Theme.border).frame(width: 1, height: 24).padding(.horizontal, 6)

            // Tap duplicates the active frame (Aseprite's New Frame); long press offers an empty one.
            Menu {
                Button("Duplicate current frame", systemImage: "plus.square.on.square") { document.addFrame() }
                Button("Empty frame", systemImage: "square.dashed") { document.addFrame(empty: true) }
            } label: {
                // Always labelled, so it isn't mistaken for the other "+" buttons nearby.
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
            .opacity(document.structure.frames.count > 1 ? 1 : 0.35)

            copyPasteButtons(compact: compact)

            Button { document.isSelectingRange = true } label: {
                pill("Select", systemImage: "checkmark.rectangle.stack", isOn: false, compact: compact)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)

            Button { newTag() } label: {
                pill("Tag", systemImage: "tag", isOn: false, compact: compact)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("t", modifiers: [.command, .option])
            .padding(.leading, 4)

            onionMenu(compact: compact)
                .padding(.leading, 4)

            Spacer(minLength: 8)

            NumberChip(
                title: "Frame duration", systemImage: "timer",
                value: Binding(get: { document.activeFrame.duration }, set: { document.setDuration($0, frameIndex: document.activeFrameIndex) }),
                range: 1...SpriteDocument.maxFrameDuration, step: durationStep, unit: "ms", presets: Self.durationPresets,
                sliderRange: 10...1000
            )
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }

    /// Quick Copy and Paste: Copy takes the selected block, or else the frame,
    /// layer or cel last tapped; Paste puts back whatever was copied.
    private func copyPasteButtons(compact: Bool) -> some View {
        HStack(spacing: 4) {
            Button { document.copyTimelineFocus() } label: {
                pill("Copy", systemImage: "doc.on.doc", isOn: false, compact: compact)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(copyHint))
            if clipboard.hasFrames {
                // Tap inserts the frames after this one; touch and hold to paste into it.
                Menu {
                    Button("Paste into this frame", systemImage: "doc.on.clipboard") { document.pasteFramesInto() }
                    Button("Paste frames after", systemImage: "doc.on.clipboard.fill") { document.pasteFrames() }
                } label: {
                    pill("Paste", systemImage: "doc.on.clipboard", isOn: false, compact: compact)
                } primaryAction: {
                    document.pasteFrames()
                }
                .menuIndicator(.hidden)
                .accessibilityHint(Text("Touch and hold to paste into this frame"))
            } else {
                Button { document.pasteTimeline() } label: {
                    pill("Paste", systemImage: "doc.on.clipboard", isOn: false, compact: compact)
                }
                .buttonStyle(.plain)
                .disabled(clipboard.content == nil)
                .opacity(clipboard.content == nil ? 0.4 : 1)
            }
        }
        .padding(.leading, 4)
    }

    private var copyHint: LocalizedStringKey {
        if document.timelineRange != nil { return "Copies the selected block" }
        switch document.timelineFocus {
        case .frame: return "Copies the current frame"
        case .layer: return "Copies the current layer"
        case .cel: return "Copies the current cel"
        }
    }

    /// Tap toggles onion skin; long press opens its settings.
    private func onionMenu(compact: Bool) -> some View {
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
            pill("Onion skin", systemImage: "square.on.square.dashed", isOn: document.onionSkin, compact: compact)
        } primaryAction: {
            document.onionSkin.toggle()
        }
        .menuIndicator(.hidden)
        .accessibilityHint(Text("Touch and hold for settings"))
    }

    private func pill(_ title: LocalizedStringKey, systemImage: String, isOn: Bool, compact: Bool = false) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(PillLabelStyle(compact: compact))
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

    /// "250ms", "4s", "1.5s": fits under a frame number.
    private static func shortDuration(_ ms: Int) -> String {
        guard ms >= 1000 else { return "\(ms)ms" }
        return ms % 1000 == 0 ? "\(ms / 1000)s" : "\((Double(ms) / 1000).formatted(.number.precision(.fractionLength(0...1))))s"
    }

    /// Long frames change in bigger steps.
    private var durationStep: Int { document.activeFrame.duration >= 1000 ? 100 : 10 }

    private static func durationLabel(_ ms: Int) -> String {
        ms >= 1000 && ms % 1000 == 0 ? "\(ms) ms · \(ms / 1000) s" : "\(ms) ms"
    }

    private func typeDuration(_ target: DurationTarget) {
        durationText = target == .activeFrame ? "\(document.activeFrame.duration)" : ""
        typingDuration = target
    }

    private func saveTypedDuration() {
        guard let ms = Int(durationText.filter(\.isNumber)), ms > 0 else { return }
        switch typingDuration {
        case .activeFrame: document.setDuration(ms, frameIndex: document.activeFrameIndex)
        case .range: document.setRangeDuration(ms)
        case nil: break
        }
    }

    // MARK: Layers

    /// The tag band buttons and, above the layers, the buttons that act on them.
    private var layerHeader: some View {
        VStack(spacing: 0) {
            if !document.structure.tags.isEmpty { tagBandHeaders }

            HStack(spacing: 0) {
                columnHeaders
                Spacer(minLength: 4)
                timelineOptions
                Menu {
                    Button("New layer", systemImage: "square.3.layers.3d") { document.addLayer() }
                    Button("New group", systemImage: "folder.badge.plus") { document.newGroup() }
                    Button("New tilemap layer", systemImage: "square.grid.3x3.fill") { document.addTilemapLayer() }
                    Button("Import image or GIF…", systemImage: "photo.stack") {
                        document.fileImport = .imageLayer
                    }
                    Section("New reference layer") {
                        Button("From Photos", systemImage: "photo.on.rectangle") { pickingReferencePhoto = true }
                        Button("From Files", systemImage: "folder") {
                            document.fileImport = .referenceLayer
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11.2, weight: .medium))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(Theme.text)
                } primaryAction: {
                    document.addLayer()
                }
                .menuIndicator(.hidden)
                .accessibilityLabel(Text("New layer"))
                .accessibilityHint(Text("Touch and hold for a reference layer"))
                .background {
                    Button("New layer") { document.addLayer() }
                        .keyboardShortcut("n", modifiers: .shift)
                        .opacity(0)
                        .accessibilityHidden(true)
                }

                IconButton(systemImage: "folder.badge.plus", label: "New group", size: 28) { document.newGroup() }
                    .accessibilityHint(Text("Groups the checked layers, or adds an empty group to drag layers into"))
                IconButton(systemImage: "trash", label: "Delete layer", size: 28) { document.deleteLayer(document.activeLayerID) }
                    .opacity(document.structure.layers.count > 1 ? 1 : 0.35)
                // Layers move by dragging them, or with Move up / Move down in their menu.
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .frame(height: headerHeight)
        }
        .frame(width: nameColumn)
    }

    /// Rows still free before the projected ones end.
    private var projectedLayerRows: Int { max(0, Self.projectedLayers - layersTopFirst.count) }

    /// Columns drawn: the sprite's frames, then projected ones up to 50.
    private var shownFrames: Int { max(document.structure.frames.count, Self.projectedFrames) }

    private var layerColumn: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
            ForEach(layersTopFirst) { layer in
                if gapBefore(layer) { dropGap(depth: document.structure.depth(of: layer)) }
                layerRow(layer)
                    .draggable(layerDragPayload(layer)) { dragPreview(Text(verbatim: layer.name)) }
                    .overlay {
                        // Dropping into a closed group: the group itself is outlined.
                        if layerDrop == LayerDropSlot(target: layer.id, drop: .into), !layer.isExpanded {
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                                .padding(2)
                                .allowsHitTesting(false)
                        }
                    }
                    .id(layer.id)
                if gapAfter(layer) {
                    dropGap(depth: document.structure.depth(of: layer) + (layer.isGroup && layerDrop?.drop == .into ? 1 : 0))
                }
            }
            }
            .onDrop(of: [.text], delegate: LayerColumnDrop(
                update: { y in layerDrop = layerDropSlot(atY: y) },
                exit: { layerDrop = nil },
                slot: { layerDrop },
                perform: { payload, slot in dropLayer(payload, at: slot) }
            ))
            // Projected layers: tapping one adds layers under the bottom one, down to it.
            ForEach(0..<projectedLayerRows, id: \.self) { row in
                Group {
                    // The same eye, lock and continuity icons as a real row, faint.
                    HStack(spacing: 0) {
                        checkBox(false).frame(width: checkColumn, height: rowHeight)
                        Image(systemName: "eye").font(.system(size: 13)).frame(width: 34, height: rowHeight)
                        Image(systemName: "lock.open").font(.system(size: 13)).frame(width: 30, height: rowHeight)
                        ContinuityIcon(isOn: false, color: Theme.muted).frame(width: 26, height: rowHeight)
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(height: rowHeight - 8)
                            .padding(.leading, 6)
                            .padding(.trailing, 10)
                    }
                    .foregroundStyle(Theme.muted)
                    .opacity(0.35)
                    .padding(.leading, 6)
                    .frame(height: rowHeight)
                    .contentShape(Rectangle())
                }
                // Only the Pencil adds layers here, so a finger scrolling the timeline can't.
                .pencilTap { _ in document.extendTimeline(toFrame: nil, layersBelow: row + 1) }
                .accessibilityLabel(Text("New layer"))
            }
        }
        .frame(width: nameColumn)
    }

    /// Above the layer buttons, the same icons act on every layer at once.
    private var columnHeaders: some View {
        let layers = document.structure.layers
        let allVisible = layers.allSatisfy(\.isVisible), allLocked = layers.allSatisfy(\.isLocked)
        let allContinuous = layers.allSatisfy(\.isContinuous)
        let checked = document.checkedLayers
        let allChecked = !layers.isEmpty && checked.count == layers.count
        return HStack(spacing: 0) {
            Button { document.toggleAllLayerChecks() } label: {
                checkBox(allChecked, partly: !checked.isEmpty && !allChecked).frame(width: checkColumn, height: headerHeight)
            }
            .accessibilityLabel(allChecked ? Text("Deselect all layers") : Text("Select all layers"))
            Button { document.toggleAllVisibility() } label: {
                Image(systemName: allVisible ? "eye" : "eye.slash")
                    .font(.system(size: 12))
                    .frame(width: 34, height: headerHeight)
            }
            .accessibilityLabel(allVisible ? Text("Hide all layers") : Text("Show all layers"))
            Button { document.toggleAllLocks() } label: {
                Image(systemName: allLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 12))
                    .frame(width: 30, height: headerHeight)
            }
            .accessibilityLabel(allLocked ? Text("Unlock all layers") : Text("Lock all layers"))
            Button { document.toggleAllContinuous() } label: {
                ContinuityIcon(isOn: allContinuous, color: Theme.muted)
                    .frame(width: 26, height: headerHeight)
            }
            .accessibilityLabel(allContinuous ? Text("Make all layers discontinuous") : Text("Make all layers continuous"))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.muted)
    }

    /// A layer's check box; `partly` is the header's when only some are checked.
    private func checkBox(_ isOn: Bool, partly: Bool = false) -> some View {
        Image(systemName: isOn ? "checkmark.square.fill" : (partly ? "minus.square.fill" : "square"))
            .font(.system(size: 14))
            .foregroundStyle(isOn || partly ? Theme.accent : Theme.muted.opacity(0.6))
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
    // MARK: Layer drag and drop

    private func gapBefore(_ layer: Layer) -> Bool {
        layerDrop == LayerDropSlot(target: layer.id, drop: .above)
    }

    private func gapAfter(_ layer: Layer) -> Bool {
        guard let slot = layerDrop, slot.target == layer.id else { return false }
        return slot.drop == .below || (slot.drop == .into && layer.isExpanded)
    }

    /// The dashed row a dragged layer would take, indented to its level.
    private func dropGap(depth: Int) -> some View {
        RoundedRectangle(cornerRadius: 7)
            .fill(Theme.accentSoft)
            .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .padding(.vertical, 3)
            .padding(.leading, 6 + CGFloat(depth) * 14)
            .padding(.trailing, 8)
            .frame(height: rowHeight)
            .allowsHitTesting(false)
    }

    /// The landing spot under `y` (from the top of the rows). The gap row
    /// itself keeps the spot it shows, so the rows don't jump under the finger.
    private func layerDropSlot(atY y: CGFloat) -> LayerDropSlot? {
        var rows: [Layer?] = []
        for layer in layersTopFirst {
            if gapBefore(layer) { rows.append(nil) }
            rows.append(layer)
            if gapAfter(layer) { rows.append(nil) }
        }
        guard let last = layersTopFirst.last else { return nil }
        let i = Int((y / rowHeight).rounded(.down))
        if i < 0 { return layerDrop }
        if i >= rows.count { return LayerDropSlot(target: last.id, drop: .below) }
        guard let layer = rows[i] else { return layerDrop }
        let f = (y - CGFloat(i) * rowHeight) / rowHeight
        if layer.isGroup {
            // Top edge: above the group; the rest: into it (a closed one has a bottom edge to go below it).
            if f < 0.3 { return LayerDropSlot(target: layer.id, drop: .above) }
            if !layer.isExpanded, f > 0.7 { return LayerDropSlot(target: layer.id, drop: .below) }
            return LayerDropSlot(target: layer.id, drop: .into)
        }
        return LayerDropSlot(target: layer.id, drop: f < 0.5 ? .above : .below)
    }

    /// A layer, or a block of selected layers, dropped on the layer column.
    private func dropLayer(_ payload: String, at slot: LayerDropSlot) {
        layerDrop = nil
        if let grabbed = RangePayload(payload) {
            document.dropRange(from: (grabbed.layer, grabbed.frame), to: (slot.target, grabbed.frame))
        } else if let id = Self.layerID(payload) {
            document.moveLayer(id, slot.drop, slot.target)
        }
    }

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
        let isChecked = document.checkedLayers.contains(layer.id)
        return HStack(spacing: 0) {
            Button { document.toggleLayerCheck(layer.id) } label: {
                checkBox(isChecked).frame(width: checkColumn, height: rowHeight)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: layer.name))
            .accessibilityValue(isChecked ? Text("Selected") : Text("Not selected"))
            .accessibilityHint(Text("Adds the layer to the timeline selection or takes it out"))
            Button { document.toggleVisibility(layer.id) } label: {
                Image(systemName: layer.isVisible ? "eye" : "eye.slash")
                    // The size of the lock and the continuity dots next to it.
                    .font(.system(size: 13))
                    .frame(width: 34, height: rowHeight)
                    .foregroundStyle(document.structure.shows(layer) ? Theme.text : Theme.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layer.isVisible ? Text("Hide \(layer.name)") : Text("Show \(layer.name)"))
            Button { document.toggleLock(layer.id) } label: {
                Image(systemName: layer.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 13))
                    .frame(width: 30, height: rowHeight)
                    .foregroundStyle(layer.isLocked ? Theme.accent : Theme.muted.opacity(0.6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(layer.isLocked ? Text("Unlock \(layer.name)") : Text("Lock \(layer.name)"))
            Button { document.toggleContinuous(layer.id) } label: {
                ContinuityIcon(isOn: layer.isContinuous, color: layer.isContinuous ? Theme.accent : Theme.muted)
                    .frame(width: 26, height: rowHeight)
            }
            .buttonStyle(.plain)
            .opacity(layer.isReference || layer.isGroup ? 0 : 1)
            .disabled(layer.isReference || layer.isGroup)
            .accessibilityLabel(layer.isContinuous ? Text("\(layer.name) is continuous") : Text("Make \(layer.name) continuous"))
            .accessibilityHint(Text("New frames link this layer's cel instead of copying it"))
            Button {
                if document.isSelectingRange { document.extendRange(layerRow: layer.id) } else { document.activeLayerID = layer.id; document.focusTimeline(.layer) }
            } label: {
                HStack(spacing: 4) {
                    if layer.isGroup {
                        Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    if layer.isTilemap {
                        Image(systemName: "square.grid.3x3.fill").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    if layer.isReference {
                        Image(systemName: "photo").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    Text(verbatim: layer.name)
                    if layer.blendMode != .normal {
                        Text(layer.blendMode.title).font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.muted)
                    }
                    if !layer.isGroup && !layer.isReference {
                        Spacer(minLength: 4)
                        LayerThumbnail(document: document, layerID: layer.id)
                            .frame(width: 34, height: rowHeight - 8)
                            .opacity(layer.isVisible ? 1 : 0.4)
                    }
                }
                    .font(.system(size: 13, weight: .medium))
                    // Underlined like Aseprite's background layer.
                    .underline(layer.isBackground)
                    .foregroundStyle(layer.isVisible ? Theme.text : Theme.muted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .frame(height: rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .leading) {
                // Groups fold and unfold with the chevron to the left of their name.
                if layer.isGroup {
                    Button { document.toggleExpanded(layer.id) } label: {
                        Image(systemName: layer.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 20, height: rowHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: -16)
                    .accessibilityLabel(layer.isExpanded ? Text("Collapse \(layer.name)") : Text("Expand \(layer.name)"))
                }
            }
            .padding(.leading, CGFloat(document.structure.depth(of: layer)) * 14 + (layer.isGroup ? 12 : 0))
            // Double tap renames, as double-click does in Aseprite.
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                guard !document.isSelectingRange else { return }
                renameText = layer.name
                renaming = layer
            })
        }
        .padding(.leading, 6)
        .frame(height: rowHeight)
        .background(inRange ? Theme.accentSoft : (isActive && !document.isSelectingRange ? Theme.accentSoft : Theme.panel))
        .overlay { if inRange { Rectangle().strokeBorder(Theme.accent, lineWidth: 2) } }
        .contextMenu {
            Button("Rename", systemImage: "pencil") {
                renameText = layer.name
                renaming = layer
            }
            Button(layer.isLocked ? LocalizedStringKey("Unlock") : LocalizedStringKey("Lock"), systemImage: "lock") { document.toggleLock(layer.id) }
            if layer.isReference {
                Section("Reference image") {
                    Button("Fit the canvas", systemImage: "arrow.down.right.and.arrow.up.left") { document.fitReference(layer.id, fill: false) }
                    Button("Fill the canvas", systemImage: "arrow.up.left.and.arrow.down.right") { document.fitReference(layer.id, fill: true) }
                    Button("Bigger", systemImage: "plus.magnifyingglass") { document.scaleReference(layer.id, by: 1.25) }
                    Button("Smaller", systemImage: "minus.magnifyingglass") { document.scaleReference(layer.id, by: 0.8) }
                }
            } else {
                Toggle(isOn: Binding(get: { layer.isContinuous }, set: { _ in document.toggleContinuous(layer.id) })) {
                    Label("Continuous", systemImage: "capsule")
                }
            }
            if !layer.isBackground && !layer.isReference {
                Picker(selection: Binding(get: { layer.blendMode }, set: { document.setBlendMode($0, layer: layer.id) })) {
                    ForEach(BlendMode.allCases) { Text($0.title).tag($0) }
                } label: {
                    Label("Blend mode", systemImage: "circle.lefthalf.filled.righthalf.striped.horizontal")
                }
                .pickerStyle(.menu)
            }
            if !layer.isBackground {
                Menu("Opacity") {
                    ForEach([100, 75, 50, 25], id: \.self) { pct in
                        Button(EditorSettings.alphaFormat.text(Double(pct) / 100)) { document.setOpacity(Double(pct) / 100, layer: layer.id) }
                    }
                }
            }
            if layer.isTilemap {
                Button("Convert to layer", systemImage: "square.3.layers.3d") { document.convertToNormalLayer(layer.id) }
            } else if !layer.isBackground, !layer.isGroup, !layer.isReference {
                Button("Convert to tilemap", systemImage: "square.grid.3x3.fill") { document.convertToTilemap(layer.id) }
            }
            if layer.isBackground {
                Button("Convert to layer", systemImage: "square.3.layers.3d.top.filled") { document.convertToLayer(layer.id) }
            } else if !layer.isReference, !document.structure.layers.contains(where: \.isBackground) {
                Button("Convert to background", systemImage: "square.3.layers.3d.bottom.filled") { document.convertToBackground(layer.id) }
            }
            Divider()
            if layer.isGroup {
                Button("Ungroup", systemImage: "folder.badge.minus") { document.ungroup(layer.id) }
            } else if !layer.isBackground {
                Button("Group", systemImage: "folder.badge.plus") { document.groupLayers([layer.id]) }
            }
            if !layer.isBackground {
                let groups = document.structure.layers.filter { group in
                    group.isGroup && group.id != layer.id && group.id != layer.parent
                        && !document.structure.descendants(of: layer.id).contains { $0.id == group.id }
                }
                if !groups.isEmpty {
                    Menu("Move into group", systemImage: "folder") {
                        ForEach(groups.reversed()) { group in
                            Button(group.name) { document.moveIntoGroup(layer.id, group: group.id) }
                        }
                    }
                }
                if layer.parent != nil {
                    Button("Take out of group", systemImage: "arrow.up.left") { document.removeFromGroup(layer.id) }
                }
            }
            Button(layer.isGroup ? LocalizedStringKey("Duplicate group") : LocalizedStringKey("Duplicate layer"), systemImage: "plus.square.on.square") { document.duplicateLayer(layer.id) }
            Button("Merge down", systemImage: "arrow.down.to.line") { document.mergeDown(layer.id) }
                .disabled(!canMergeDown(layer))
            Button("Flatten", systemImage: "square.stack.3d.down.forward") { document.flatten() }
                .disabled(document.structure.layers.count <= 1)
            Button("Select layers", systemImage: "checkmark.rectangle.stack") {
                document.isSelectingRange = true
                document.extendRange(layerRow: layer.id)
            }
            if !layer.isGroup {
                Button("Copy layer", systemImage: "doc.on.doc") { document.copyLayer(layer.id) }
            }
            Button("Paste layers above", systemImage: "doc.on.clipboard") {
                document.activeLayerID = layer.id
                document.pasteLayers()
            }
            .disabled(!clipboard.hasLayers)
            Divider()
            Button("Move up", systemImage: "arrow.up") { document.moveLayer(layer.id, by: 1) }
                .disabled(layer.isBackground)
            Button("Move down", systemImage: "arrow.down") { document.moveLayer(layer.id, by: -1) }
                .disabled(layer.isBackground || document.structure.layers.first.map { $0.isBackground && document.structure.layers.count > 1 && document.structure.layers[1].id == layer.id } == true)
            Divider()
            Button(layer.isGroup ? LocalizedStringKey("Delete group and its layers") : LocalizedStringKey("Delete layer"), systemImage: "trash", role: .destructive) { document.deleteLayer(layer.id) }
                .disabled(document.structure.layers.count <= 1)
        }
    }

    private func canMergeDown(_ layer: Layer) -> Bool {
        guard let index = document.structure.layers.firstIndex(where: { $0.id == layer.id }), index > 0 else { return false }
        let lower = document.structure.layers[index - 1]
        return !layer.isReference && !lower.isReference && !layer.isGroup && !lower.isGroup && layer.parent == lower.parent
    }

    private func loadReferencePhoto() {
        guard let item = referencePhoto else { return }
        referencePhoto = nil
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                document.addReferenceLayer(imageData: data)
            }
        }
    }


    // MARK: Tags

    /// The focused band, if it still exists.
    private var focusedBand: Int? {
        document.focusedTagBand.flatMap { $0 < document.structure.tagBandCount ? $0 : nil }
    }

    /// Tag bands on screen: only the focused one when a band is focused.
    private var visibleBands: [Int] {
        if let focusedBand { return [focusedBand] }
        return Array(0..<max(1, document.structure.tagBandCount))
    }

    /// No room for tags until the sprite has some, like Aseprite.
    private var tagRowHeight: CGFloat {
        document.structure.tags.isEmpty ? 0 : CGFloat(visibleBands.count) * tagLaneHeight + (document.structure.tagBandCount > 1 ? 4 : 1)
    }

    /// Next to each tag band, the button that focuses it (only with several bands).
    private var tagBandHeaders: some View {
        let bandCount = document.structure.tagBandCount
        return VStack(spacing: 0) {
            ForEach(Array(visibleBands.enumerated()), id: \.element) { row, band in
                HStack(spacing: 4) {
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
        let frames = document.structure.frames.count
        let bands = visibleBands
        let shown = document.structure.tagBands.filter { bands.contains($0.band) }
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(shown, id: \.tag.id) { item in
                tagBar(item.tag, band: item.band)
                    .offset(x: CGFloat(item.tag.from) * celWidth + 2, y: CGFloat(bands.firstIndex(of: item.band) ?? 0) * tagLaneHeight + (document.structure.tagBandCount > 1 ? 2 : 1))
            }
        }
        .frame(width: CGFloat(frames) * celWidth, height: tagRowHeight, alignment: .topLeading)
    }

    private func tagBar(_ tag: FrameTag, band: Int) -> some View {
        let light = Int(tag.color.r) * 3 + Int(tag.color.g) * 6 + Int(tag.color.b) > 1400
        return Button { editingTag = tag } label: {
            HStack(spacing: 4) {
                Image(systemName: tag.direction.systemImage).font(.system(size: tagLaneHeight > 16 ? 9 : 7, weight: .bold))
                Text(verbatim: tag.name).font(.system(size: tagLaneHeight > 16 ? 11 : 9.5, weight: .semibold)).lineLimit(1)
                if tag.repeatCount > 0 {
                    Text(verbatim: "×\(tag.repeatCount)").font(.system(size: 10, weight: .semibold, design: .monospaced))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(light ? Theme.onAccent : .white)
            .padding(.horizontal, 6)
            .frame(width: CGFloat(tag.frameCount) * celWidth - 4, height: tagLaneHeight - 4, alignment: .leading)
            .background(tag.color.color, in: RoundedRectangle(cornerRadius: tagLaneHeight > 16 ? 6 : 4))
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
        let frames = document.structure.frames
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
            ForEach(layersTopFirst) { layer in
                // Keeps the cels in line with the gap a dragged layer opens.
                if gapBefore(layer) { Color.clear.frame(height: rowHeight) }
                HStack(spacing: 0) {
                    if layer.isGroup {
                        Rectangle()
                            .fill(Theme.chip.opacity(0.5))
                            .frame(width: CGFloat(frames.count) * celWidth, height: rowHeight)
                            .contentShape(Rectangle())
                            .onTapGesture { document.activeLayerID = layer.id }
                    } else if layer.isReference {
                        // A reference image is the same in every frame: one strip, no cels.
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Theme.chip)
                            .overlay(Label("Reference image", systemImage: "photo").labelStyle(.iconOnly).foregroundStyle(Theme.muted))
                            .frame(width: CGFloat(frames.count) * celWidth - 4, height: rowHeight - 8)
                            .frame(width: CGFloat(frames.count) * celWidth, height: rowHeight)
                            .contentShape(Rectangle())
                            .onTapGesture { document.activeLayerID = layer.id }
                    } else {
                        ForEach(frames.indices, id: \.self) { index in
                            celButton(layer: layer, frameIndex: index, frame: frames[index])
                        }
                    }
                    if showsDropColumn {
                        RoundedRectangle(cornerRadius: 7)
                            .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: celWidth - 4, height: rowHeight - 6)
                            .frame(width: celWidth)
                            .contentShape(Rectangle())
                            .dropDestination(for: String.self) { items, _ in dropRange(items, layer: layer.id, frame: frames.count) }
                            .accessibilityLabel(Text("After the last frame"))
                    }
                    // Projected frames: tapping one adds empty frames up to it.
                    projectedCels(columns: (frames.count + (showsDropColumn ? 1 : 0))..<shownFrames, rows: 1) { column, _ in
                        document.extendTimeline(toFrame: column, layersBelow: 0, layer: layer.id)
                    }
                }
                .frame(height: rowHeight)
                .background(layer.id == document.activeLayerID && !document.isSelectingRange ? Theme.accentSoft : .clear)
                if gapAfter(layer) { Color.clear.frame(height: rowHeight) }
            }
            }
            .overlay(alignment: .topLeading) { rangeOutline }
            // The active frame's column, tinted like the active layer's row: they cross on the active cel.
            .background(alignment: .topLeading) {
                if !document.isSelectingRange {
                    Rectangle()
                        .fill(Theme.accentSoft)
                        .frame(width: celWidth, height: CGFloat(layersTopFirst.count) * rowHeight)
                        .offset(x: CGFloat(document.activeFrameIndex) * celWidth)
                        .allowsHitTesting(false)
                }
            }
            // Projected layers, across every column.
            if projectedLayerRows > 0 {
                projectedCels(columns: 0..<shownFrames, rows: projectedLayerRows) { column, row in
                    document.extendTimeline(toFrame: column, layersBelow: row + 1)
                }
            }
        }
        .padding(.trailing, 16)
    }

    /// The frame numbers (and tags above them), scrolled with the cels.
    private var frameHeaderStrip: some View {
        let frames = document.structure.frames
        let activeTag = document.activeTag
        let usualDuration = document.structure.usualFrameDuration
        return VStack(alignment: .leading, spacing: 0) {
            if !document.structure.tags.isEmpty { tagRow }
            HStack(spacing: 0) {
                ForEach(frames.indices, id: \.self) { index in
                    frameHeader(index, count: frames.count, inActiveTag: activeTag?.contains(index) ?? false,
                                duration: usualDuration.flatMap { frames[index].duration != $0 ? frames[index].duration : nil })
                        .overlay(alignment: .bottom) { onionMark(index) }
                }
                if showsDropColumn {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: celWidth, height: headerHeight)
                        .dropDestination(for: String.self) { items, _ in dropRange(items, layer: nil, frame: frames.count) }
                }
                ForEach((frames.count + (showsDropColumn ? 1 : 0))..<max(shownFrames, frames.count + (showsDropColumn ? 1 : 0)), id: \.self) { index in
                    Text(verbatim: "\(index + firstFrame)")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.muted.opacity(0.4))
                        .frame(width: celWidth, height: headerHeight)
                        .contentShape(Rectangle())
                        .pencilTap { _ in document.extendTimeline(toFrame: index, layersBelow: 0) }
                        .accessibilityLabel(Text("New frame"))
                }
            }
            .simultaneousGesture(scrub)
        }
        .padding(.trailing, 16)
        .fixedSize()
    }

    /// Dashed placeholders for frames and layers that don't exist yet, drawn in one
    /// pass; `tap` gets the column and row tapped.
    private func projectedCels(columns: Range<Int>, rows: Int, tap: @escaping (Int, Int) -> Void) -> some View {
        let width = CGFloat(max(0, columns.count)) * celWidth, height = CGFloat(rows) * rowHeight
        return Canvas { context, _ in
            let style = StrokeStyle(lineWidth: 1, dash: [3, 3])
            for row in 0..<rows {
                for column in 0..<columns.count {
                    let rect = CGRect(x: CGFloat(column) * celWidth + 2.5, y: CGFloat(row) * rowHeight + 3.5, width: celWidth - 5, height: rowHeight - 7)
                    context.stroke(Path(roundedRect: rect, cornerRadius: 6), with: .color(Theme.border), style: style)
                }
            }
        }
        .frame(width: width, height: height)
        .pencilTap { location in
            let column = columns.lowerBound + min(columns.count - 1, max(0, Int(location.x / celWidth)))
            let row = min(rows - 1, max(0, Int(location.y / rowHeight)))
            tap(column, row)
        }
        .accessibilityHidden(true)
    }

    /// A border around each run of selected rows, like Aseprite's range
    /// (checked layers needn't be next to each other).
    @ViewBuilder
    private var rangeOutline: some View {
        if let range = document.timelineRange {
            let rows = layersTopFirst.map { range.layers.contains($0.id) }
            ForEach(Self.runs(of: rows), id: \.lowerBound) { run in
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.accent, lineWidth: 2.5)
                    .frame(width: CGFloat(range.frames.count) * celWidth, height: CGFloat(run.count) * rowHeight - 2)
                    .offset(x: CGFloat(range.frames.lowerBound) * celWidth, y: CGFloat(run.lowerBound) * rowHeight + 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// The runs of consecutive `true`s.
    static func runs(of flags: [Bool]) -> [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        var start: Int?
        for (i, on) in (flags + [false]).enumerated() {
            if on, start == nil { start = i }
            if !on, let s = start { runs.append(s...(i - 1)); start = nil }
        }
        return runs
    }

    /// Drops a dragged block on (`layer`, `frame`); a nil layer keeps the block's layers (drops on frame numbers).
    private func dropRange(_ items: [String], layer: UUID?, frame: Int) -> Bool {
        guard let grabbed = items.first.flatMap(RangePayload.init) else { return false }
        if grabbed.isCel {
            document.moveCel(from: (grabbed.layer, grabbed.frame), to: (layer ?? grabbed.layer, frame))
        } else {
            document.dropRange(from: (grabbed.layer, grabbed.frame), to: (layer ?? grabbed.layer, frame))
        }
        return true
    }

    /// Under the frames the onion skin shows: red before, blue after (gray without tint).
    @ViewBuilder
    private func onionMark(_ index: Int) -> some View {
        if let offset = document.onionOffset(of: index) {
            let tint = document.onionSettings.tint
            Capsule()
                .fill(!tint ? Theme.muted : (offset < 0 ? PixelColor.onionPrevious.color : PixelColor.onionNext.color))
                .opacity(1 - 0.25 * Double(abs(offset) - 1))
                .frame(width: celWidth - 18, height: 3)
                .padding(.bottom, 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Dragging along the frame numbers moves through the animation (Aseprite's
    /// and Procreate's scrubbing); touch and hold a number to drag it elsewhere.
    private var scrub: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { drag in
                guard !document.isSelectingRange else { return }
                let index = Int((drag.location.x / celWidth).rounded(.down))
                guard document.structure.frames.indices.contains(index), index != document.activeFrameIndex else { return }
                document.goToFrame(index)
            }
    }

    /// `duration` is set when this frame lasts longer or shorter than most.
    private func frameHeader(_ index: Int, count: Int, inActiveTag: Bool, duration: Int?) -> some View {
        let isActive = index == document.activeFrameIndex
        let range = document.timelineRange
        let inRange = range.map { $0.kind == .frames && $0.frames.contains(index) } ?? false
        let payload = inRange ? RangePayload(layer: document.structure.layers.last!.id, frame: index).string : "frame:\(index)"
        return Button {
            if document.isSelectingRange { document.extendRange(frameIndex: index) } else { document.goToFrame(index); document.focusTimeline(.frame) }
        } label: {
            VStack(spacing: 1) {
                Text(verbatim: "\(index + firstFrame)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                if let duration {
                    Text(verbatim: Self.shortDuration(duration))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 3)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(Theme.accentText)
                }
            }
                .foregroundStyle(inRange ? Theme.accentText : (isActive ? Theme.onAccent : (inActiveTag ? Theme.text : Theme.muted)))
                .frame(width: celWidth, height: headerHeight)
                .background {
                    if inRange {
                        Theme.accentSoft
                    } else if isActive {
                        // The active frame in a pill, so it's found at a glance.
                        RoundedRectangle(cornerRadius: 6).fill(Theme.accent).padding(.horizontal, 3).padding(.vertical, 3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Frame \(index + firstFrame)"))
        .accessibilityValue(duration.map { Text(verbatim: "\($0) ms") } ?? Text(verbatim: ""))
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
                newTag()
            }
            Button("Select frames", systemImage: "checkmark.rectangle.stack") {
                document.isSelectingRange = true
                document.extendRange(frameIndex: index)
            }
            Button("Copy frame", systemImage: "doc.on.doc") { document.copyFrame(at: index) }
            Button("Paste into this frame", systemImage: "doc.on.clipboard") {
                document.goToFrame(index)
                document.pasteFramesInto()
            }
            .disabled(!clipboard.hasFrames)
            Button("Paste frames after", systemImage: "doc.on.clipboard.fill") {
                document.goToFrame(index)
                document.pasteFrames()
            }
            .disabled(!clipboard.hasFrames)
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
        let filled = document.structure.cels[key] != nil
        let opacity = document.structure.celOpacity[key] ?? 1
        let zIndex = document.structure.celZIndex[key] ?? 0
        let isActive = layer.id == document.activeLayerID && frameIndex == document.activeFrameIndex
        let isActiveFrame = frameIndex == document.activeFrameIndex
        let inRange = document.timelineRange.map { $0.layers.contains(layer.id) && $0.frames.contains(frameIndex) } ?? false
        let dot = isActive && !document.isSelectingRange ? Theme.onAccent : Theme.dot
        let links = linkNeighbours(layer: layer, frameIndex: frameIndex)
        let background: Color = document.isSelectingRange
            ? (inRange ? Theme.accentSoft : Theme.raised)
            : (isActive ? Theme.accent : (isActiveFrame ? Theme.columnActive : Theme.raised))
        let cel = Button {
            if document.isSelectingRange {
                document.extendRange(layer: layer.id, frameIndex: frameIndex)
            } else {
                if document.timelineRange != nil { document.endRangeSelection() }
                document.selectCel(layer: layer.id, frameIndex: frameIndex)
                document.focusTimeline(.cel)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7).fill(background)
                if filled {
                    // Linked cels join into one long pill, as in Aseprite's timeline.
                    ZStack {
                        HStack(spacing: 0) {
                            Rectangle().fill(links.before ? dot : .clear)
                            Rectangle().fill(links.after ? dot : .clear)
                        }
                        .frame(height: 10)
                        .padding(.horizontal, -2)
                        Circle().fill(dot).frame(width: 10, height: 10)
                    }
                    .compositingGroup()
                    // Translucent cels show a fainter dot.
                    .opacity(0.35 + 0.65 * opacity)
                } else {
                    HStack(spacing: 0) {
                        Rectangle().fill(links.before ? dot : .clear).frame(height: 2)
                        Color.clear.frame(width: 10)
                        Rectangle().fill(links.after ? dot : .clear).frame(height: 2)
                    }
                    .padding(.horizontal, -2)
                    Circle().strokeBorder(dot, lineWidth: 1.5).frame(width: 10, height: 10)
                }
            }
            .frame(width: celWidth - 4, height: rowHeight - 6)
            .overlay(alignment: .topTrailing) {
                // Drawn higher or lower than its layer in this frame.
                if zIndex != 0 && filled {
                    Text(verbatim: zIndex > 0 ? "+\(zIndex)" : "\u{2212}\(-zIndex)")
                        .font(.system(size: 8, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 2)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 3))
                        .offset(x: 1, y: -1)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                // Cels picked earlier stay outlined while they're still the selection.
                if inRange && !document.isSelectingRange {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.accent, lineWidth: 2)
                }
            }
            .frame(width: celWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(filled ? Text("Cel \(layer.name), frame \(frameIndex + firstFrame)") : Text("Cel \(layer.name), frame \(frameIndex + firstFrame), empty"))
        .accessibilityValue(document.structure.isLinked(key) ? Text("Linked") : Text(verbatim: ""))
        .dropDestination(for: String.self) { items, _ in dropRange(items, layer: layer.id, frame: frameIndex) }
        .contextMenu {
            if filled {
                Menu("Cel opacity") {
                    ForEach([100, 75, 50, 25], id: \.self) { pct in
                        Button(EditorSettings.alphaFormat.text(Double(pct) / 100)) { document.setCelOpacity(Double(pct) / 100, layer: layer.id, frameIndex: frameIndex) }
                    }
                }
            }
            if document.structure.isLinked(key) {
                Button("Unlink cel", systemImage: "personalhotspot.slash") { document.unlinkCel(layer: layer.id, frameIndex: frameIndex) }
            }
            if filled {
                // Aseprite's Cel Properties > Z-Index: drawn above or below other layers in this frame only.
                Menu {
                    Button("Up one layer", systemImage: "arrow.up") { document.setCelZIndex(zIndex + 1, layer: layer.id, frameIndex: frameIndex) }
                    Button("Down one layer", systemImage: "arrow.down") { document.setCelZIndex(zIndex - 1, layer: layer.id, frameIndex: frameIndex) }
                    Button("Reset", systemImage: "arrow.uturn.backward") { document.setCelZIndex(0, layer: layer.id, frameIndex: frameIndex) }
                        .disabled(zIndex == 0)
                } label: {
                    Label { Text("Z-index: \(zIndex)") } icon: { Image(systemName: "square.3.layers.3d") }
                }
            }
            Button("Select cels", systemImage: "checkmark.rectangle.stack") {
                document.isSelectingRange = true
                document.extendRange(layer: layer.id, frameIndex: frameIndex)
            }
            if filled {
                Button("Copy cel", systemImage: "doc.on.doc") { document.copyCel(layer: layer.id, frameIndex: frameIndex) }
            }
            Button("Paste cels here", systemImage: "doc.on.clipboard") {
                document.selectCel(layer: layer.id, frameIndex: frameIndex)
                document.pasteCels()
            }
            .disabled(!clipboard.hasCels)
        }
        // Selected cels drag the whole block (Aseprite drags it from its border).
        return Group {
            if inRange, document.timelineRange?.kind == .cels {
                cel.draggable(RangePayload(layer: layer.id, frame: frameIndex).string) {
                    dragPreview(document.timelineRange.map { r in
                        Text(verbatim: "\(r.frames.count) × \(r.layers.count)")
                    } ?? Text(verbatim: ""))
                }
            } else if filled && !document.isSelectingRange {
                // A drawn cel can be dragged by its dot to another frame or layer.
                cel.draggable(RangePayload(layer: layer.id, frame: frameIndex, isCel: true).string) {
                    dragPreview(Text(verbatim: "1 × 1"))
                }
            } else {
                cel
            }
        }
    }

    /// Whether this cel is linked with the cel in the previous / next frame of its layer.
    private func linkNeighbours(layer: Layer, frameIndex: Int) -> (before: Bool, after: Bool) {
        let sprite = document.structure
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
    /// A single cel dragged by its dot, not a selected block.
    var isCel = false

    init(layer: UUID, frame: Int, isCel: Bool = false) {
        self.layer = layer
        self.frame = frame
        self.isCel = isCel
    }

    init?(_ string: String) {
        let parts = string.split(separator: ":")
        guard parts.count == 3, parts[0] == "range" || parts[0] == "cel",
              let layer = UUID(uuidString: String(parts[1])), let frame = Int(parts[2]) else { return nil }
        self.init(layer: layer, frame: frame, isCel: parts[0] == "cel")
    }

    var string: String { "\(isCel ? "cel" : "range"):\(layer.uuidString):\(frame)" }
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

/// Aseprite's continuity icon: two separate dots for a regular layer, one
/// joined bar for a continuous layer (new frames link its cel).
struct ContinuityIcon: View {
    let isOn: Bool
    var color: Color

    var body: some View {
        Group {
            if isOn {
                Capsule().fill(color).frame(width: 15, height: 7)
            } else {
                HStack(spacing: 3) {
                    Circle().fill(color.opacity(0.5)).frame(width: 6, height: 6)
                    Circle().fill(color.opacity(0.5)).frame(width: 6, height: 6)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Icon and title, or just the icon when space is short (the title stays for VoiceOver).
private struct PillLabelStyle: LabelStyle {
    let compact: Bool

    func makeBody(configuration: Configuration) -> some View {
        if compact {
            Label(configuration).labelStyle(.iconOnly)
        } else {
            Label(configuration)
        }
    }
}

/// What a layer shows in the current frame, cropped to its content, small,
/// next to its name (as Pixquare does). It's its own view so that a committed stroke redraws the
/// thumbnails and not the whole timeline; cels that didn't change keep their image.
private struct LayerThumbnail: View {
    let document: SpriteDocument
    let layerID: UUID
    @State private var cache = Cache()

    final class Cache {
        var cel: PixelImage?
        var image: CGImage?
    }

    var body: some View {
        // `sprite` reads `revision`, so this follows every committed change.
        let sprite = document.sprite
        let cel = document.isPlaying ? cache.cel : sprite.frames.indices.contains(document.activeFrameIndex)
            ? sprite.cel(layer: layerID, frame: sprite.frames[document.activeFrameIndex].id) : nil
        ZStack {
            Checkerboard(cell: 3)
            if let image = image(for: cel, ratio: sprite.pixelRatio) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.border))
        .accessibilityHidden(true)
    }

    private func image(for cel: PixelImage?, ratio: PixelRatio) -> CGImage? {
        // While playing, thumbnails hold still: redrawing every layer's on every
        // frame costs more than it shows.
        if document.isPlaying, cache.cel != nil { return cache.image }
        guard let cel else { return nil }
        // Comparing an untouched cel is cheap: its pixels still share storage.
        if cache.cel != cel {
            cache.cel = cel
            // Cropped to what's drawn, so a small element still reads at this size.
            cache.image = SelectionMask.opaquePixels(of: cel).bounds
                .map { cel.cropped(to: $0).scaled(x: ratio.width, y: ratio.height).makeCGImage() } ?? nil
        }
        return cache.image
    }
}

/// Where a layer dragged in the timeline would land.
struct LayerDropSlot: Equatable {
    var target: UUID
    var drop: SpriteDocument.LayerDrop
}

/// One drop target for the whole layer column, so the landing spot follows
/// the finger row by row (and between rows) instead of per row.
private struct LayerColumnDrop: DropDelegate {
    let update: (CGFloat) -> Void
    let exit: () -> Void
    let slot: () -> LayerDropSlot?
    let perform: (String, LayerDropSlot) -> Void

    func dropEntered(info: DropInfo) { update(info.location.y) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info.location.y)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { exit() }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first, let slot = slot() else { exit(); return false }
        let perform = perform
        _ = provider.loadTransferable(type: String.self) { result in
            let payload = try? result.get()
            Task { @MainActor in perform(payload ?? "", slot) }
        }
        return true
    }
}

extension View {
    /// Runs `action` for a tap of the Apple Pencil only (with the point
    /// tapped); fingers pass through to scroll. Also a VoiceOver action.
    func pencilTap(_ action: @escaping (CGPoint) -> Void) -> some View {
        overlay(PencilTapView(action: action))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action(.zero) }
    }
}

private struct PencilTapView: UIViewRepresentable {
    let action: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) { context.coordinator.action = action }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: (CGPoint) -> Void
        init(action: @escaping (CGPoint) -> Void) { self.action = action }
        @objc func tapped(_ gesture: UITapGestureRecognizer) { action(gesture.location(in: gesture.view)) }
    }
}
