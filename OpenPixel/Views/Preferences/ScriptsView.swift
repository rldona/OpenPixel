import SwiftUI

/// The scripts added to OpenPixel, run from a sprite's … > Scripts menu.
struct ScriptsView: View {
    @State private var store = ScriptStore.shared
    @State private var importing = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Button("Add script…", systemImage: "plus") { importing = true }
            } footer: {
                Text("Aseprite scripts (.lua) run in a sandbox: they change the open sprite and can't reach files or the network. Parts of Aseprite's API aren't available yet; a script that needs them stops and says which.")
            }
            if !store.scripts.isEmpty {
                Section("Installed") {
                    ForEach(store.scripts) { script in
                        Label { Text(verbatim: script.name) } icon: { Image(systemName: "curlybraces") }
                    }
                    .onDelete { offsets in
                        for index in offsets { store.remove(store.scripts[index]) }
                    }
                }
            }
        }
        .navigationTitle("Scripts")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.luaScript, .plainText]) { result in
            do {
                try store.install(contentsOf: result.get())
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert("Couldn't add the script", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }
}
