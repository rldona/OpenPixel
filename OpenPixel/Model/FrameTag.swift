import Foundation
import SwiftUI

/// Loop direction of a tag, as in Aseprite.
/// https://www.aseprite.org/docs/tags/
enum AnimationDirection: String, Codable, CaseIterable, Identifiable, Sendable {
    case forward, reverse, pingPong, pingPongReverse

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .forward: "Forward"
        case .reverse: "Reverse"
        case .pingPong: "Ping-pong"
        case .pingPongReverse: "Ping-pong reverse"
        }
    }

    var systemImage: String {
        switch self {
        case .forward: "arrow.right"
        case .reverse: "arrow.left"
        case .pingPong: "arrow.left.arrow.right"
        case .pingPongReverse: "arrow.right.arrow.left"
        }
    }
}

/// A named range of frames, e.g. "idle" or "run". `from` and `to` are frame indices.
struct FrameTag: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var from: Int
    var to: Int
    var color: PixelColor
    var direction: AnimationDirection = .forward
    /// How many times the animation plays; 0 loops forever.
    var repeatCount = 0

    var frameCount: Int { to - from + 1 }

    func contains(_ frame: Int) -> Bool { frame >= from && frame <= to }

    static let colors: [PixelColor] = [
        "#E5484D", "#F76B15", "#FFC53D", "#46A758", "#0090FF", "#8E4EC6", "#D6409F", "#8B8D98"
    ].compactMap(PixelColor.init(hex:))
}

enum Playback {
    /// Frame indices for one cycle over `from...to` in the given direction.
    /// Ping-pong doesn't repeat the end frames: 0 1 2 3 2 1.
    static func cycle(from: Int, to: Int, direction: AnimationDirection) -> [Int] {
        guard from < to else { return [from] }
        let up = Array(from...to)
        let down = Array(up.reversed())
        switch direction {
        case .forward: return up
        case .reverse: return down
        case .pingPong: return up + down.dropFirst().dropLast()
        case .pingPongReverse: return down + up.dropFirst().dropLast()
        }
    }
}

extension Sprite {
    /// The innermost tag that contains `frame`.
    func tag(containing frame: Int) -> FrameTag? {
        tags.filter { $0.contains(frame) }.min { $0.frameCount < $1.frameCount }
    }

    /// Frames to play starting from `frame`: its tag's cycle, or every frame in order.
    /// With a focused tag band only that band's tags play; outside them, the band's first tag.
    func playbackCycle(at frame: Int, band: Int? = nil) -> (frames: [Int], repeatCount: Int) {
        var tag = tag(containing: frame)
        if let band {
            let inBand = tagBands.filter { $0.band == band }.map(\.tag)
            tag = inBand.first { $0.contains(frame) } ?? inBand.first
        }
        if let tag {
            return (Playback.cycle(from: tag.from, to: tag.to, direction: tag.direction), tag.repeatCount)
        }
        return (Array(frames.indices), 0)
    }

    /// Inserts a frame and shifts tags. Inserting right after a tag's last frame extends the tag.
    mutating func insertFrame(_ frame: Frame, at index: Int) {
        frames.insert(frame, at: index)
        for i in tags.indices {
            if index <= tags[i].from {
                tags[i].from += 1
                tags[i].to += 1
            } else if index <= tags[i].to + 1 {
                tags[i].to += 1
            }
        }
    }

    /// Removes a frame with its cels; tags shrink, and disappear when left empty.
    mutating func removeFrame(at index: Int) {
        let id = frames.remove(at: index).id
        cels = cels.filter { $0.key.frame != id }
        normalizeLinks()
        tags = tags.compactMap { tag in
            var tag = tag
            if index < tag.from {
                tag.from -= 1
                tag.to -= 1
            } else if index <= tag.to {
                if tag.from == tag.to { return nil }
                tag.to -= 1
            }
            return tag
        }
    }

    /// Moves a frame's content to another position. Tags keep their positions.
    mutating func moveFrame(from source: Int, to destination: Int) {
        let frame = frames.remove(at: source)
        frames.insert(frame, at: destination)
    }
}
