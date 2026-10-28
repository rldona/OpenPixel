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
    @State private var errorMessage: String?
    /// An Aseprite extension just added by opening it from Files.
    @State private var addedExtension: AsepriteExtension?
    /// A script just added by opening it from Files.
    @State private var addedScript: ScriptStore.Script?

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 20)]

    private var visibleItems: [SpriteSummary] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return store.items.filter { item in
            filter.includes(item) && (trimmed.isEmpty || item.name.localizedCaseInsensitiveContains(trimmed))
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
                            ForEach(visibleItems) { item in
                                Button { path.append(item.id) } label: { SpriteCard(item: item) }
                                    .buttonStyle(.plain)
                                    .contextMenu { contextMenu(for: item) }
                            }
                        }
                        if visibleItems.isEmpty && !query.isEmpty {
                            ContentUnavailableView.search(text: query)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 28)
                }
            }
            .background(Theme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                EditorContainer(id: id)
            }
            .sheet(isPresented: $showingNewSprite) {
                NewSpriteView { name, sprite in
                    attempt { path.append(try store.create(name: name, sprite: sprite)) }
                }
            }
            .sheet(isPresented: $showingPreferences) { PreferencesView() }
            .sheet(item: $exporting) { ExportView(document: $0) }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.aseprite, .png, .gif, .jpeg]) { result in
                attempt { path.append(try store.importFile(at: result.get())) }
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
        HStack(alignment: .center) {
            Text("Projects")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Theme.text)
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
        Button("Delete", systemImage: "trash", role: .destructive) { deleting = item }
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

/// Loads a sprite from disk and keeps it saved while editing.
struct EditorContainer: View {
    let id: UUID
    @Environment(DocumentStore.self) private var store
    @State private var document: SpriteDocument?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let document {
                EditorView(document: document)
            } else if let loadError {
                ContentUnavailableView("Couldn't open the project", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else {
                ProgressView()
            }
        }
        .task(id: id) {
            await store.flush()
            do { document = try store.load(id) } catch { loadError = error.localizedDescription }
        }
    }
}

extension SpriteDocument: Identifiable {}
