import SwiftUI

struct PreferencesView: View {
    @AppStorage(AppLanguage.storageKey) private var language = AppLanguage.english
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.dark
    @AppStorage(AccentChoice.storageKey) private var accent = AccentChoice.ember
    /// Saved when the sheet closes: saving rebuilds every view, which would close it.
    @State private var accentChoice = AccentChoice.current
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    // Editor preferences, after Aseprite's Edit > Preferences.
    @AppStorage(EditorSettings.checkerSizeKey) private var checkerSize = 0
    @AppStorage(EditorSettings.checkerLightKey) private var checkerLight = ""
    @AppStorage(EditorSettings.checkerDarkKey) private var checkerDark = ""
    @AppStorage(EditorSettings.pixelGridColorKey) private var pixelGridColor = ""
    @AppStorage(EditorSettings.tileGridColorKey) private var tileGridColor = ""
    @AppStorage(EditorSettings.alphaFormatKey) private var alphaFormat = AlphaFormat.percent
    @AppStorage(EditorSettings.rewindOnStopKey) private var rewindOnStop = false
    @AppStorage(EditorSettings.undoLimitKey) private var undoLimit = EditorSettings.defaultUndoLimit
    @AppStorage(EditorSettings.fingerInputKey) private var fingerInput = FingerInput.automatic
    @AppStorage(EditorSettings.pencilDoubleTapKey) private var pencilDoubleTap = PencilAction.system
    @AppStorage(EditorSettings.pencilSqueezeKey) private var pencilSqueeze = PencilAction.system
    @AppStorage(EditorSettings.mirroredLayoutKey) private var mirroredLayout = false
    @State private var confirmingReset = false

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
                    Picker("Layout", selection: $mirroredLayout) {
                        Label("Tools on the left", systemImage: "sidebar.left").tag(false)
                        Label("Tools on the right", systemImage: "sidebar.right").tag(true)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Layout")
                } footer: {
                    Text("Tools on the right and the color panel on the left suits left-handed drawing, like Aseprite's mirrored layout.")
                }

                canvasSection
                gridSection

                Section {
                    Picker("Alpha and opacity", selection: $alphaFormat) {
                        ForEach(AlphaFormat.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Rewind on stop", isOn: $rewindOnStop)
                    Picker("Undo steps", selection: $undoLimit) {
                        ForEach(EditorSettings.undoLimits, id: \.self) { Text(verbatim: "\($0)").tag($0) }
                    }
                } header: {
                    Text("Editor")
                } footer: {
                    Text("Rewind on stop goes back to the frame playback started from. More undo steps use more memory with big sprites.")
                }

                Section {
                    Picker("Finger", selection: $fingerInput) {
                        ForEach(FingerInput.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Double tap", selection: $pencilDoubleTap) {
                        ForEach(PencilAction.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Squeeze", selection: $pencilSqueeze) {
                        ForEach(PencilAction.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Apple Pencil and touch")
                } footer: {
                    Text("Two fingers always move and zoom the canvas. Squeeze needs an Apple Pencil Pro.")
                }

                Section {
                    NavigationLink {
                        KeyboardShortcutsView()
                    } label: {
                        Label("Keyboard shortcuts", systemImage: "keyboard")
                    }
                    NavigationLink {
                        ExtensionsView()
                    } label: {
                        Label("Extensions", systemImage: "puzzlepiece.extension")
                    }
                    NavigationLink {
                        ScriptsView()
                    } label: {
                        Label("Scripts", systemImage: "curlybraces")
                    }
                }

                Section {
                    Button("Reset editor preferences", role: .destructive) { confirmingReset = true }
                } footer: {
                    Text("Language, appearance and accent color are kept.")
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
        .confirmationDialog("Reset editor preferences?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { EditorSettings.reset() }
        }
    }

    /// The checkerboard behind transparent pixels (Aseprite's Background preferences).
    private var canvasSection: some View {
        let dark = colorScheme == .dark
        return Section {
            Picker("Checker size", selection: $checkerSize) {
                ForEach(EditorSettings.checkerSizes, id: \.self) { size in
                    if size == 0 { Text("Automatic").tag(size) } else { Text(verbatim: "\(size) px").tag(size) }
                }
            }
            ColorPicker("Light squares", selection: StoredColor.binding($checkerLight, fallback: dark ? PixelColor(r: 69, g: 69, b: 69) : PixelColor(r: 236, g: 236, b: 236)), supportsOpacity: false)
            ColorPicker("Dark squares", selection: StoredColor.binding($checkerDark, fallback: dark ? PixelColor(r: 54, g: 54, b: 54) : PixelColor(r: 212, g: 212, b: 212)), supportsOpacity: false)
            if !checkerLight.isEmpty || !checkerDark.isEmpty {
                Button("Use the appearance's colors") { checkerLight = ""; checkerDark = "" }
            }
        } header: {
            Text("Transparent background")
        } footer: {
            Text("Automatic keeps the squares a similar size on screen at any zoom.")
        }
    }

    private var gridSection: some View {
        let dark = colorScheme == .dark
        return Section {
            ColorPicker("Pixel grid", selection: StoredColor.binding($pixelGridColor, fallback: dark ? PixelColor(r: 255, g: 255, b: 255, a: 56) : PixelColor(r: 0, g: 0, b: 0, a: 46)))
            ColorPicker("Tile grid", selection: StoredColor.binding($tileGridColor, fallback: PixelColor(Theme.accent.opacity(0.7))))
            if !pixelGridColor.isEmpty || !tileGridColor.isEmpty {
                Button("Use the default colors") { pixelGridColor = ""; tileGridColor = "" }
            }
        } header: {
            Text("Grid")
        } footer: {
            Text("The color's opacity is the grid's opacity.")
        }
    }

    private func icon(for appearance: AppAppearance) -> String {
        switch appearance {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}
