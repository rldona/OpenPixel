import SwiftUI

/// What's left of the timeline when it's pushed down out of the way (as in
/// Calco): play, the frame number and a scrubber. Tap the chevron, or drag
/// the capsule up, to bring the timeline back.
struct TimelineCapsule: View {
    @Bindable var document: SpriteDocument
    let expand: () -> Void
    @AppStorage("timelineFirstFrame") private var firstFrame = 1

    var body: some View {
        HStack(spacing: 12) {
            Button { document.togglePlayback() } label: {
                Image(systemName: document.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Play or pause"))
            .keyboardShortcut(document.isTransforming || document.isBuildingShape ? nil : KeyboardShortcut(.return, modifiers: []))

            Text(verbatim: "\(document.activeFrameIndex + firstFrame) / \(document.structure.frames.count - 1 + firstFrame)")
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.text)
                .fixedSize()

            if document.structure.frames.count > 1 {
                Slider(value: frameBinding, in: 0...Double(document.structure.frames.count - 1), step: 1)
                    .tint(Theme.accent)
                    .frame(width: 140)
                    .accessibilityLabel(Text("Frame"))
            }

            Button(action: expand) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Show timeline"))
        }
        .padding(.horizontal, 10)
        .background(Theme.panel.opacity(0.95), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .gesture(
            DragGesture(minimumDistance: 12).onEnded { drag in
                if drag.translation.height < -20 { expand() }
            }
        )
        .background {
            // The frame keys keep working with the timeline hidden.
            Group {
                Button("Previous frame") { document.goToFrame(document.activeFrameIndex - 1) }
                    .keyboardShortcut(document.isTransforming ? nil : KeyboardShortcut(.leftArrow, modifiers: []))
                Button("Next frame") { document.goToFrame(document.activeFrameIndex + 1) }
                    .keyboardShortcut(document.isTransforming ? nil : KeyboardShortcut(.rightArrow, modifiers: []))
            }
            .opacity(0)
            .accessibilityHidden(true)
        }
    }

    private var frameBinding: Binding<Double> {
        Binding(
            get: { Double(document.activeFrameIndex) },
            set: { document.goToFrame(Int($0.rounded())) }
        )
    }
}
