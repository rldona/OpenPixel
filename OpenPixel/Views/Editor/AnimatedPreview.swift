import SwiftUI

/// The side panel's preview, like Aseprite's Preview Window: it shows the
/// current frame, and its own play button runs the animation (the current
/// tag, or every frame) while you keep drawing.
struct AnimatedPreview: View {
    let document: SpriteDocument
    @State private var playing = false
    @State private var shown: Int?
    @State private var cache = FrameImageCache()

    var body: some View {
        let frame = playing ? (shown ?? document.activeFrameIndex) : document.activeFrameIndex
        PixelThumbnail(image: image(frame))
            .overlay(alignment: .bottomTrailing) {
                if document.sprite.frames.count > 1 {
                    Button { playing.toggle() } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(playing ? Theme.onAccent : Theme.text)
                            .frame(width: 36, height: 36)
                            .background(playing ? Theme.accent : Theme.panel.opacity(0.9), in: Circle())
                            .overlay(Circle().strokeBorder(Theme.border))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                    .accessibilityLabel(playing ? Text("Pause preview") : Text("Play preview"))
                }
            }
            .task(id: playing) {
                guard playing else { shown = nil; return }
                await play()
            }
    }

    private func image(_ frame: Int) -> CGImage? {
        cache.image(frame, of: document.sprite, revision: document.revision)
    }

    private func play() async {
        var position = 0
        while !Task.isCancelled {
            let sprite = document.sprite
            let cycle = sprite.playbackCycle(at: document.activeFrameIndex).frames
            guard !cycle.isEmpty else { return }
            position %= cycle.count
            let index = min(cycle[position], sprite.frames.count - 1)
            shown = index
            let duration = sprite.frames[index].duration
            try? await Task.sleep(for: .milliseconds(duration))
            position += 1
        }
    }
}

/// Frame images for one revision of the sprite, made as they're first shown,
/// so a playing preview doesn't recomposite every frame on every tick.
final class FrameImageCache {
    private var revision = -1
    private var images: [Int: CGImage] = [:]

    func image(_ frame: Int, of sprite: Sprite, revision: Int) -> CGImage? {
        if revision != self.revision {
            images = [:]
            self.revision = revision
        }
        if let cached = images[frame] { return cached }
        let made = sprite.composite(frameIndex: frame).makeCGImage()
        images[frame] = made
        return made
    }
}
