import SwiftUI

struct PreferencesView: View {
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.english
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.dark
    @AppStorage(AccentChoice.storageKey) private var accent = AccentChoice.ember
    /// Saved when the sheet closes: saving rebuilds every view, which would close it.
    @State private var accentChoice = AccentChoice.current
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Language", selection: $language) {
                        ForEach(AppLanguage.allCases) { Text(verbatim: $0.nativeName).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Language")
                }

                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { Label($0.title, systemImage: icon(for: $0)).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Appearance")
                }

                Section {
                    HStack(spacing: 14) {
                        ForEach(AccentChoice.allCases) { choice in
                            Button { accentChoice = choice } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(choice.swatch)
                                        .frame(width: 44, height: 44)
                                        .overlay {
                                            if accentChoice == choice {
                                                Image(systemName: "checkmark").font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                                            }
                                        }
                                        .padding(3)
                                        .overlay(Circle().strokeBorder(accentChoice == choice ? choice.swatch : .clear, lineWidth: 2))
                                    Text(choice.title).font(.system(size: 12)).foregroundStyle(Theme.muted)
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(choice.title))
                            .accessibilityAddTraits(accentChoice == choice ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Accent color")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                    Link(destination: URL(string: "https://github.com/rldona/OpenPixel")!) {
                        Label("Source code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("OpenPixel is open source under the MIT license.")
                }
            }
            .navigationTitle("Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        // A presented sheet keeps its own appearance; apply the choice here too so it changes live.
        .preferredColorScheme(appearance.colorScheme)
        .tint(accentChoice.swatch)
        .onDisappear { if accent != accentChoice { accent = accentChoice } }
    }

    private func icon(for appearance: AppAppearance) -> String {
        switch appearance {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}
