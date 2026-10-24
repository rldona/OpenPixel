import SwiftUI

@main
struct OpenPixelApp: App {
    @State private var store = DocumentStore()
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.english
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.dark

    var body: some Scene {
        WindowGroup {
            GalleryView()
                .environment(store)
                .environment(\.locale, language.locale)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.accent)
                // Full screen: no status bar, and the home indicator fades while drawing.
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}
