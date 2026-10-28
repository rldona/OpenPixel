import SwiftUI
import UniformTypeIdentifiers

/// Home screen: the project gallery.
struct GalleryView: View {
    enum Filter: CaseIterable, Identifiable {
        case all, animated, still
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .all: "All"
            case .animated: "Animations"
            case .still: "Still"
            }
        }

        func includes(_ item: SpriteSummary) -> Bool {
            switch self {
            case .all: true
            case .animated: item.frameCount > 1
            case .still: item.frameCount == 1
            }
        }
    }

    @Environment(DocumentStore.self) private var store
    @State private var path: [UUID] = []
    @State private var filter = Filter.all
    @State private var query = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    @State private var showingNewSprite = false
    @State private var showingImporter = false
    @State private var showingPreferences = false
    @State private var renaming: SpriteSummary?
    @State private var renameText = ""
    @State private var deleting: SpriteSummary?
    /// A project exported straight from its card, without opening it.
    @State private var exporting: SpriteDocument?
    /// The folder on screen; nil is the home screen.
    @State private var openFolder: UUID?
    /// Projects going into the folder being created (none for an empty one).
    @State private var newFolderProjects: [UUID]?
    @State private var folderName = ""
    @State private var renamingFolder: ProjectFolder?
    @State private var deletingFolder: ProjectFolder?
    @State private var backDropTargeted = false
    @State private var errorMessage: String?
    /// An Aseprite extension just added by opening it from Files.
    @State private var addedExtension: AsepriteExtension?
    /// A script just added by opening it from Files.
    @State private var addedScript: ScriptStore.Script?

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 20)]

    /// The open folder's folders and projects, or the home screen's, in
    /// their order; a search lists the matching projects of every folder.
    private var visibleEntries: [GalleryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.isEmpty else {
            return store.items.filter { filter.includes($0) && $0.name.localizedCaseInsensitiveContains(trimmed) }.map(GalleryEntry.project)
        }
        return store.entries(in: openFolder).filter { entry in
            if case .project(let item) = entry { return filter.includes(item) }
            return true
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        titleRow
                        LazyVGrid(columns: columns, spacing: 20) {
                            if query.isEmpty { NewSpriteCard { showingNewSprite = true } }
                            // Drag any card onto the side of another to put it there, or onto
                            // the middle of a folder to put it inside.
                            ForEach(visibleEntries) { entry in
                                switch entry {
                                case .folder(let folder):
                                    FolderCard(folder: folder) { withAnimation(.snappy) { openFolder = folder.id } }
                                        .contextMenu { contextMenu(for: folder) }
                                        .draggable(Self.folderPayload + folder.id.uuidString) {
                                            DragPreview(image: store.allItems(in: folder.id).first?.thumbnail, name: folder.name, systemImage: "folder.fill")
                                        }
                                        .modifier(CardDrop(holds: true) { drop($0, on: folder.id, zone: $1) })
                                case .project(let item):
                                    Button { path.append(item.id) } label: { SpriteCard(item: item) }
                                        .buttonStyle(.plain)
                                        .contextMenu { contextMenu(for: item) }
                                        .draggable(item.id.uuidString) { DragPreview(image: item.thumbnail, name: item.name) }
                                        .modifier(CardDrop(holds: false) { drop($0, on: item.id, zone: $1) })
                                }
                            }
                        }
                        if visibleEntries.isEmpty && !query.isEmpty {
                            ContentUnavailableView.search(text: query)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if visibleEntries.isEmpty && openFolder != nil {
                            ContentUnavailableView("This folder is empty", systemImage: "folder",
                                                   description: Text("Touch and hold a project and choose Move to folder, or drag it onto the folder."))
                                .frame(maxWidth: .infinity)
                                .padding(.top, 20)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 28)
                }
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                EditorContainer(id: id, store: store)
            }
            .sheet(isPresented: $showingNewSprite) {
                NewSpriteView { name, sprite in
                    attempt { path.append(try store.create(name: name, sprite: sprite, in: openFolder)) }
                }
            }
            .sheet(isPresented: $showingPreferences) { PreferencesView() }
            .sheet(item: $exporting) { ExportView(document: $0) }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.aseprite, .png, .gif, .jpeg]) { result in
                attempt { path.append(try store.importFile(at: result.get(), into: openFolder)) }
            }
            // Files, AirDrop or Mail opening a sprite in OpenPixel.
            .onOpenURL { url in
                if url.pathExtension.lowercased() == "aseprite-extension" {
                    attempt { addedExtension = try ExtensionStore.shared.install(contentsOf: url) }
                } else if url.pathExtension.lowercased() == "lua" {
                    attempt { addedScript = try ScriptStore.shared.install(contentsOf: url) }
                } else {
                    attempt { path = [try store.importFile(at: url)] }
                }
            }
            .alert(Text("“\(addedScript?.name ?? "")” added"), isPresented: Binding(get: { addedScript != nil }, set: { if !$0 { addedScript = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Run it from a sprite: … > Scripts.")
            }
            .alert(Text("“\(addedExtension?.displayName ?? "")” added"), isPresented: Binding(get: { addedExtension != nil }, set: { if !$0 { addedExtension = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                if !(addedExtension?.commands ?? []).isEmpty {
                    Text("Its commands are in a sprite's … > Scripts.")
                } else {
                    Text("Its palettes are in the palette's Load preset menu, its dithering matrices in the gradient tool.")
                }
            }
            .alert("Rename project", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let item = renaming { attempt { try store.rename(item.id, to: renameText) } }
                }
            }
            .alert("New folder", isPresented: Binding(get: { newFolderProjects != nil }, set: { if !$0 { newFolderProjects = nil } })) {
                TextField("Name", text: $folderName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    let projects = newFolderProjects ?? []
                    let name = folderName.trimmingCharacters(in: .whitespaces)
                    attempt {
                        let folder = try store.createFolder(name: name.isEmpty ? L10n.string("Folder") : name, in: openFolder)
                        try store.move(projects, to: folder)
                    }
                }
            }
            .alert("Rename folder", isPresented: Binding(get: { renamingFolder != nil }, set: { if !$0 { renamingFolder = nil } })) {
                TextField("Name", text: $folderName)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let folder = renamingFolder { attempt { try store.renameFolder(folder.id, to: folderName) } }
                }
            }
            .confirmationDialog(
                Text("Delete “\(deletingFolder?.name ?? "")”?"),
                isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete folder", role: .destructive) {
                    if let folder = deletingFolder { attempt { try store.deleteFolder(folder.id) } }
                }
            } message: {
                Text("What's in it moves up a level.")
            }
            .onChange(of: store.folders) {
                // The open folder was deleted (or the files changed under it).
                if let openFolder, store.folder(openFolder) == nil { self.openFolder = nil }
            }
            .confirmationDialog(
                Text("Delete “\(deleting?.name ?? "")”?"),
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let item = deleting { attempt { try store.delete(item.id) } }
                }
            } message: {
                Text("This can't be undone.")
            }
            .alert("Something went wrong", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .task {
            store.forgetOpened()
            // Let background saves from the editor finish before reading the files.
            await store.flush()
            store.reload()
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                PixelLogo(size: 32)
                PixelWordmark(pixel: 3)
            }
            Spacer(minLength: 16)

            if searching {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("Search projects", text: $query)
                        .focused($searchFocused)
                        .submitLabel(.search)
                    Button {
                        query = ""
                        searching = false
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Close search"))
                }
                .padding(.horizontal, 12)
                .frame(width: 280, height: 44)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
            } else {
                headerIconButton("magnifyingglass", label: "Search") {
                    searching = true
                    searchFocused = true
                }
                .keyboardShortcut("f", modifiers: .command)
            }

            headerIconButton("folder.badge.plus", label: "New folder") { startNewFolder(with: []) }

            headerIconButton("gearshape", label: "Preferences") { showingPreferences = true }
                .keyboardShortcut(",", modifiers: .command)

            Button { showingImporter = true } label: {
                Label("Import", systemImage: "square.and.arrow.down")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
            }
            .buttonStyle(.plain)

            Button { showingNewSprite = true } label: {
                Label("New sprite", systemImage: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(.horizontal, 40)
        .frame(height: 76)
        .background(Theme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private func headerIconButton(_ systemImage: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: 14) {
            if let folder = openFolder.flatMap(store.folder) {
                let parent = folder.parent.flatMap(store.folder)
                Button { withAnimation(.snappy) { openFolder = parent?.id } } label: {
                    Label { parent.map { Text($0.name) } ?? Text("Projects") } icon: { Image(systemName: "chevron.left") }
                        .lineLimit(1)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(backDropTargeted ? Theme.accent : Theme.border, lineWidth: backDropTargeted ? 2 : 1))
                }
                .buttonStyle(.plain)
                // Drop a project or folder here to take it up a level.
                .dropDestination(for: String.self) { payloads, _ in
                    drop(payloads, into: parent?.id)
                    return true
                } isTargeted: { backDropTargeted = $0 }
                Text(folder.name)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
            } else {
                Text("Projects")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Theme.text)
            }
            Spacer()
            HStack(spacing: 4) {
                ForEach(Filter.allCases) { f in
                    Button { filter = f } label: {
                        Text(f.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(filter == f ? Theme.text : Theme.muted)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(filter == f ? Theme.selection : .clear, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == f ? .isSelected : [])
                }
            }
            .padding(4)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        }
    }

    @ViewBuilder
    private func contextMenu(for item: SpriteSummary) -> some View {
        Button("Rename", systemImage: "pencil") {
            renameText = item.name
            renaming = item
        }
        Button("Duplicate", systemImage: "plus.square.on.square") {
            attempt { try store.duplicate(item.id) }
        }
        Button("Export", systemImage: "square.and.arrow.up") {
            attempt { exporting = try store.load(item.id) }
        }
        let current = store.folderOf[item.id]
        Menu("Move to folder", systemImage: "folder") {
            ForEach(store.folders.filter { $0.id != current }) { folder in
                Button(folderPath(folder.id), systemImage: "folder") { attempt { try store.move([item.id], to: folder.id) } }
            }
            Button("New folder…", systemImage: "folder.badge.plus") { startNewFolder(with: [item.id]) }
            if let current {
                Divider()
                Button("Remove from folder", systemImage: "folder.badge.minus") {
                    attempt { try store.move([item.id], to: store.folder(current)?.parent) }
                }
            }
        }
        Button("Delete", systemImage: "trash", role: .destructive) { deleting = item }
    }

    /// "Characters › Dummy", to tell nested folders apart in menus.
    private func folderPath(_ id: UUID) -> String {
        store.path(to: id).map(\.name).joined(separator: " › ")
    }

    /// Cards dropped beside `target` go right before or after it, coming
    /// into this folder if they were elsewhere; dropped into a folder, they
    /// go inside it. A search's results have no order to change.
    private func drop(_ payloads: [String], on target: UUID, zone: DropZone) {
        if zone == .into { return drop(payloads, into: target) }
        guard query.isEmpty else { return }
        let here = openFolder
        withAnimation(.snappy) {
            attempt {
                for payload in payloads {
                    if payload.hasPrefix(Self.folderPayload) {
                        guard let id = UUID(uuidString: String(payload.dropFirst(Self.folderPayload.count))), id != target,
                              let folder = store.folder(id) else { continue }
                        if folder.parent != here { try store.moveFolder(id, to: here) }
                        // It can't come here if here is inside it.
                        guard store.folder(id)?.parent == here else { continue }
                        try store.place(id, by: target, after: zone == .after, in: here)
                    } else if let id = UUID(uuidString: payload), id != target {
                        if store.folderOf[id] != here { try store.move([id], to: here) }
                        try store.place(id, by: target, after: zone == .after, in: here)
                    }
                }
            }
        }
    }

    static let folderPayload = "openpixel-folder:"

    /// Projects (their ids) or folders (`folderPayload` + id) dropped on a folder.
    private func drop(_ payloads: [String], into folder: UUID?) {
        attempt {
            for payload in payloads {
                if payload.hasPrefix(Self.folderPayload) {
                    guard let id = UUID(uuidString: String(payload.dropFirst(Self.folderPayload.count))), id != folder else { continue }
                    try store.moveFolder(id, to: folder)
                } else if let id = UUID(uuidString: payload) {
                    try store.move([id], to: folder)
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for folder: ProjectFolder) -> some View {
        Button("Rename", systemImage: "pencil") {
            folderName = folder.name
            renamingFolder = folder
        }
        // Anywhere but inside itself, or where it already is.
        let targets = store.folders.filter { target in
            target.id != folder.parent && !store.path(to: target.id).contains { $0.id == folder.id }
        }
        Menu("Move to folder", systemImage: "folder") {
            ForEach(targets) { target in
                Button(folderPath(target.id), systemImage: "folder") { attempt { try store.moveFolder(folder.id, to: target.id) } }
            }
            if let parent = folder.parent {
                Divider()
                Button("Remove from folder", systemImage: "folder.badge.minus") {
                    attempt { try store.moveFolder(folder.id, to: store.folder(parent)?.parent) }
                }
            }
        }
        Button("Delete folder", systemImage: "trash", role: .destructive) { deletingFolder = folder }
    }

    private func startNewFolder(with projects: [UUID]) {
        folderName = L10n.string("Folder")
        newFolderProjects = projects
    }

    private func attempt(_ work: () throws -> Void) {
        do { try work() } catch { errorMessage = error.localizedDescription }
    }
}

private struct NewSpriteCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 56, height: 56)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16))
                Text("New sprite").font(.headline).foregroundStyle(Theme.text)
                Text(verbatim: "16 · 32 · 64 · ") + Text("custom")
            }
            .font(.footnote)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 262)
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.strongBorder, style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A folder on the home screen: up to four of its projects, its name and
/// how many it holds. Projects dropped on it go in.
private struct FolderCard: View {
    let folder: ProjectFolder
    let open: () -> Void
    @Environment(DocumentStore.self) private var store

    private var count: Text {
        let projects = store.items(in: folder.id).count, folders = store.folders(in: folder.id).count
        let projectText = projects == 1 ? Text("1 project") : Text("\(projects) projects")
        guard folders > 0 else { return projectText }
        return projectText + Text(verbatim: " · ") + (folders == 1 ? Text("1 folder") : Text("\(folders) folders"))
    }

    var body: some View {
        // The thumbnails come from inner folders too.
        let items = store.allItems(in: folder.id)
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    ForEach(0..<4, id: \.self) { i in
                        Group {
                            if i < items.count {
                                PixelThumbnail(image: items[i].thumbnail)
                            } else {
                                Theme.raised
                            }
                        }
                        .frame(height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(6)
                .frame(height: 186)
                .background(Theme.panel)
                VStack(alignment: .leading, spacing: 4) {
                    Label { Text(folder.name).lineLimit(1) } icon: { Image(systemName: "folder.fill").foregroundStyle(Theme.accent) }
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    count
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(height: 262, alignment: .top)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Opens the folder"))
    }
}

enum DropZone { case before, after, into }

/// Where a dragged card lands on another: its left or right side puts it
/// before or after; the middle of a folder (`holds`) puts it inside. A bar
/// beside the card, or a frame around the folder, shows which.
private struct CardDrop: ViewModifier {
    let holds: Bool
    let perform: ([String], DropZone) -> Void
    @State private var width: CGFloat = 1
    @State private var zone: DropZone?

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .overlay {
                // Half the grid's spacing out, so the bar sits between two cards.
                switch zone {
                case .before:
                    HStack { bar.offset(x: -12.5); Spacer() }
                case .after:
                    HStack { Spacer(); bar.offset(x: 12.5) }
                case .into:
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Theme.accent.opacity(0.1))
                        .strokeBorder(Theme.accent, lineWidth: 3)
                case nil:
                    EmptyView()
                }
            }
            .onDrop(of: [.plainText], delegate: Delegate(width: width, holds: holds, zone: $zone, perform: perform))
    }

    private var bar: some View {
        Capsule().fill(Theme.accent).frame(width: 5).padding(.vertical, 8)
    }

    struct Delegate: DropDelegate {
        let width: CGFloat
        let holds: Bool
        @Binding var zone: DropZone?
        let perform: ([String], DropZone) -> Void

        private func zone(at x: CGFloat) -> DropZone {
            if holds {
                if x < width * 0.25 { return .before }
                if x > width * 0.75 { return .after }
                return .into
            }
            return x < width / 2 ? .before : .after
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            zone = zone(at: info.location.x)
            return DropProposal(operation: .move)
        }

        func dropExited(info: DropInfo) { zone = nil }

        func performDrop(info: DropInfo) -> Bool {
            let zone = zone(at: info.location.x)
            self.zone = nil
            let providers = info.itemProviders(for: [.plainText])
            guard !providers.isEmpty else { return false }
            Task { @MainActor in
                var payloads: [String] = []
                for provider in providers {
                    let text: String? = await withCheckedContinuation { done in
                        _ = provider.loadTransferable(type: String.self) { done.resume(returning: try? $0.get()) }
                    }
                    if let text { payloads.append(text) }
                }
                perform(payloads, zone)
            }
            return true
        }
    }
}

/// What follows the finger while dragging a project or a folder. It's drawn
/// apart from the gallery, without its environment, so it can't read the store.
private struct DragPreview: View {
    let image: CGImage?
    let name: String
    var systemImage: String?

    var body: some View {
        VStack(spacing: 6) {
            PixelThumbnail(image: image)
                .frame(width: 120, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Label { Text(name).lineLimit(1) } icon: { systemImage.map { Image(systemName: $0) } }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.text)
        }
        .padding(8)
        .frame(width: 140)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct SpriteCard: View {
    let item: SpriteSummary
    @Environment(DocumentStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The frame shown while an animated sprite plays in a loop.
    @State private var frame: CGImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PixelThumbnail(image: frame ?? item.thumbnail)
                // Animated sprites play in a loop while their card is on screen,
                // so you can see what each one does.
                .task(id: "\(item.id)-\(item.modified.timeIntervalSince1970)-\(reduceMotion)") {
                    frame = nil
                    guard !reduceMotion, let animation = await store.animation(for: item) else { return }
                    var i = 0
                    while !Task.isCancelled {
                        frame = animation.frames[i]
                        try? await Task.sleep(for: .milliseconds(max(20, animation.durations[i])))
                        i = (i + 1) % animation.frames.count
                    }
                }
                .frame(height: 186)
                .overlay(alignment: .topTrailing) {
                    if item.frameCount > 1 {
                        Label { Text(verbatim: "\(item.frameCount)") } icon: { Image(systemName: "play.fill") }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
                            .padding(10)
                            .accessibilityLabel(Text("\(item.frameCount) frames"))
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.name).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                    Spacer(minLength: 4)
                }
                (Text(verbatim: "\(item.width)×\(item.height) · ")
                    + (item.frameCount == 1 ? Text("1 frame") : Text("\(item.frameCount) frames"))
                    + Text(verbatim: " · ")
                    + Text(item.modified, format: .relative(presentation: .named)))
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(height: 262, alignment: .top)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Opens a sprite for the editor, which keeps it saved. The sprite is read
/// up front, so the editor slides in already drawn.
struct EditorContainer: View {
    let id: UUID
    @State private var document: SpriteDocument?
    @State private var loadError: String?

    init(id: UUID, store: DocumentStore) {
        self.id = id
        do {
            _document = State(initialValue: try store.open(id))
        } catch {
            _loadError = State(initialValue: error.localizedDescription)
        }
    }

    var body: some View {
        if let document {
            EditorView(document: document)
        } else {
            ContentUnavailableView("Couldn't open the project", systemImage: "exclamationmark.triangle", description: Text(loadError ?? ""))
        }
    }
}

extension SpriteDocument: Identifiable {}
