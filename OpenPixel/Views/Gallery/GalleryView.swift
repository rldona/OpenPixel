import SwiftUI
import UniformTypeIdentifiers

struct GalleryView: View {
    @Environment(DocumentStore.self) private var store
    @State private var path: [UUID] = []
    @State private var showingNewSprite = false
    @State private var showingImporter = false
    @State private var renaming: SpriteSummary?
    @State private var renameText = ""
    @State private var deleting: SpriteSummary?
    @State private var errorMessage: String?

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 20)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    NewSpriteCard { showingNewSprite = true }
                    ForEach(store.items) { item in
                        Button { path.append(item.id) } label: { SpriteCard(item: item) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Renombrar", systemImage: "pencil") {
                                    renameText = item.name
                                    renaming = item
                                }
                                Button("Duplicar", systemImage: "plus.square.on.square") {
                                    attempt { try store.duplicate(item.id) }
                                }
                                Button("Eliminar", systemImage: "trash", role: .destructive) { deleting = item }
                            }
                    }
                }
                .padding(32)
            }
            .background(Theme.background)
            .navigationTitle("Mis sprites")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Importar PNG", systemImage: "square.and.arrow.down") { showingImporter = true }
                    Button("Nuevo sprite", systemImage: "plus") { showingNewSprite = true }
                        .keyboardShortcut("n", modifiers: .command)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                EditorContainer(id: id)
            }
            .sheet(isPresented: $showingNewSprite) {
                NewSpriteView { name, sprite in
                    attempt { path.append(try store.create(name: name, sprite: sprite)) }
                }
            }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.png, .gif, .jpeg]) { result in
                attempt { path.append(try store.importImage(at: result.get())) }
            }
            .alert("Renombrar sprite", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Nombre", text: $renameText)
                Button("Cancelar", role: .cancel) {}
                Button("Guardar") {
                    if let item = renaming { attempt { try store.rename(item.id, to: renameText) } }
                }
            }
            .confirmationDialog(
                "¿Eliminar «\(deleting?.name ?? "")»?",
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible
            ) {
                Button("Eliminar", role: .destructive) {
                    if let item = deleting { attempt { try store.delete(item.id) } }
                }
            } message: {
                Text("No se puede deshacer.")
            }
            .alert("Algo ha fallado", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Aceptar", role: .cancel) {}
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
                Text("Nuevo sprite").font(.headline).foregroundStyle(Theme.text)
                Text("16 · 32 · 64 · personalizado").font(.footnote).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 252)
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(hex: 0x3A3A43), style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SpriteCard: View {
    let item: SpriteSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PixelThumbnail(image: item.thumbnail)
                .frame(height: 176)
                .overlay(alignment: .topTrailing) {
                    if item.frameCount > 1 {
                        Label("\(item.frameCount)", systemImage: "play.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                            .padding(10)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name).font(.headline).lineLimit(1)
                Text("\(item.width)×\(item.height) · \(item.frameCount) \(item.frameCount == 1 ? "frame" : "frames") · \(item.modified.formatted(.relative(presentation: .named)))")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(height: 252, alignment: .top)
        .background(Color(hex: 0x1A1A1F))
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
                ContentUnavailableView("No se pudo abrir", systemImage: "exclamationmark.triangle", description: Text(loadError))
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
