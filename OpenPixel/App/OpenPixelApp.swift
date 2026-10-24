import SwiftUI

@main
struct OpenPixelApp: App {
    @State private var store = DocumentStore()

    var body: some Scene {
        WindowGroup {
            GalleryView()
                .environment(store)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
