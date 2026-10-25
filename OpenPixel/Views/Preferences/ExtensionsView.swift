import SwiftUI
import UniformTypeIdentifiers

/// Aseprite extensions (Preferences > Extensions): their palettes show up in the
/// palette's Load preset menu, their dithering matrices in the gradient tool.
struct ExtensionsView: View {
    @State private var store = ExtensionStore.shared
    @State private var importing = false
    @State private var errorMessage: String?
    @State private var removing: AsepriteExtension?

    var body: some View {
        List {
            Section {
                Button("Add extension…", systemImage: "plus") { importing = true }
            } footer: {
                Text("Aseprite extensions (.aseprite-extension) with palettes, dithering matrices or scripts. Their commands are in a sprite's … > Scripts. Themes, languages and keys are Aseprite's own and aren't used.")
            }
            if !store.installed.isEmpty {
                Section("Installed") {
                    ForEach(store.installed) { package in
                        row(package)
                            .swipeActions {
                                Button("Uninstall", role: .destructive) { removing = package }
                            }
                            .contextMenu {
                                Button("Uninstall", systemImage: "trash", role: .destructive) { removing = package }
                            }
                    }
                }
            }
        }
        .navigationTitle("Extensions")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.asepriteExtension, .zip]) { result in
            do {
                try store.install(contentsOf: result.get())
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert("Couldn't add the extension", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(Text("Uninstall “\(removing?.displayName ?? "")”?"),
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Uninstall", role: .destructive) { if let package = removing { store.remove(package.id) } }
        } message: {
            Text("Sprites keep the colors they already use.")
        }
    }

    private func row(_ package: AsepriteExtension) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(verbatim: package.displayName).font(.body.weight(.medium))
                if !package.version.isEmpty {
                    Text(verbatim: package.version).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            if !package.author.isEmpty {
                Text(verbatim: package.author).font(.caption).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 12) {
                switch package.palettes.count {
                case 0: EmptyView()
                case 1: Label("1 palette", systemImage: "swatchpalette")
                case let n: Label("\(n) palettes", systemImage: "swatchpalette")
                }
                switch package.commands?.count ?? 0 {
                case 0: EmptyView()
                case 1: Label("1 command", systemImage: "curlybraces")
                case let n: Label("\(n) commands", systemImage: "curlybraces")
                }
                switch package.ditheringMatrices.count {
                case 0: EmptyView()
                case 1: Label("1 dithering matrix", systemImage: "checkerboard.rectangle")
                case let n: Label("\(n) dithering matrices", systemImage: "checkerboard.rectangle")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
            // A strip of each palette's colors.
            ForEach(package.palettes) { palette in
                HStack(spacing: 6) {
                    Text(verbatim: palette.id).font(.caption).frame(width: 110, alignment: .leading).lineLimit(1)
                    HStack(spacing: 0) {
                        ForEach(Array(palette.colors.prefix(32).enumerated()), id: \.offset) { _, color in
                            color.color.frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 12)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        }
        .padding(.vertical, 2)
    }
}
