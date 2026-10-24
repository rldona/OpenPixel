import SwiftUI

@main
struct OpenPixelApp: App {
    @State private var store = DocumentStore()
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.english
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.dark
    @AppStorage(AccentChoice.storageKey) private var accent = AccentChoice.ember

    var body: some Scene {
        WindowGroup {
            GalleryView()
                // Theme colors are read when views are built: a new accent rebuilds them.
                .id(accent)
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
