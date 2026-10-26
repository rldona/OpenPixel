import Foundation

struct Palette: Identifiable, Hashable {
    let name: String
    let colors: [PixelColor]
    var id: String { name }

    init(name: String, colors: [PixelColor]) {
        self.name = name
        self.colors = colors
    }

    private init(_ name: String, _ hexes: [String]) {
        self.init(name: name, colors: hexes.compactMap(PixelColor.init(hex:)))
    }

    /// Aseprite's default palette.
    static let db32 = Palette("DawnBringer 32", [
        "#000000", "#222034", "#45283C", "#663931", "#8F563B", "#DF7126", "#D9A066", "#EEC39A",
        "#FBF236", "#99E550", "#6ABE30", "#37946E", "#4B692F", "#524B24", "#323C39", "#3F3F74",
        "#306082", "#5B6EE1", "#639BFF", "#5FCDE4", "#CBDBFC", "#FFFFFF", "#9BADB7", "#847E87",
        "#696A6A", "#595652", "#76428A", "#AC3232", "#D95763", "#D77BBA", "#8F974A", "#8A6F30"
    ])

    static let pico8 = Palette("PICO-8", [
        "#000000", "#1D2B53", "#7E2553", "#008751", "#AB5236", "#5F574F", "#C2C3C7", "#FFF1E8",
        "#FF004D", "#FFA300", "#FFEC27", "#00E436", "#29ADFF", "#83769C", "#FF77A8", "#FFCCAA"
    ])

    static let sweetie16 = Palette("Sweetie 16", [
        "#1A1C2C", "#5D275D", "#B13E53", "#EF7D57", "#FFCD75", "#A7F070", "#38B764", "#257179",
        "#29366F", "#3B5DC9", "#41A6F6", "#73EFF7", "#F4F4F4", "#94B0C2", "#566C86", "#333C57"
    ])

    static let endesga32 = Palette("Endesga 32", [
        "#BE4A2F", "#D77643", "#EAD4AA", "#E4A672", "#B86F50", "#733E39", "#3E2731", "#A22633",
        "#E43B44", "#F77622", "#FEAE34", "#FEE761", "#63C74D", "#3E8948", "#265C42", "#193C3E",
        "#124E89", "#0099DB", "#2CE8F5", "#FFFFFF", "#C0CBDC", "#8B9BB4", "#5A6988", "#3A4466",
        "#262B44", "#181425", "#FF0044", "#68386C", "#B55088", "#F6757A", "#E8B796", "#C28569"
    ])

    static let db16 = Palette("DawnBringer 16", [
        "#140C1C", "#442434", "#30346D", "#4E4A4E", "#854C30", "#346524", "#D04648", "#757161",
        "#597DCE", "#D27D2C", "#8595A1", "#6DAA2C", "#D2AA99", "#6DC2CA", "#DAD45E", "#DEEED6"
    ])

    static let gameBoy = Palette("Game Boy", ["#0F380F", "#306230", "#8BAC0F", "#9BBC0F"])

    static let grays = Palette("Grays", (0..<16).map { i in
        let v = i * 17
        return String(format: "#%02X%02X%02X", v, v, v)
    })

    /// No colors: build your own with the palette's + (the primary color goes in).
    static let empty = Palette(name: "Empty", colors: [])

    static let presets: [Palette] = [.db32, .pico8, .sweetie16, .endesga32, .db16, .gameBoy, .grays]

    // MARK: Default palette

    private static let defaultKey = "defaultPalette"

    /// The palette saved with "Save as default palette", if any.
    static var savedDefault: Palette? {
        guard let hexes = UserDefaults.standard.stringArray(forKey: defaultKey), !hexes.isEmpty else { return nil }
        return Palette(L10n.string("My default"), hexes)
    }

    static func saveDefault(_ colors: [PixelColor]) {
        UserDefaults.standard.set(colors.map(\.hex), forKey: defaultKey)
    }

    static func clearSavedDefault() {
        UserDefaults.standard.removeObject(forKey: defaultKey)
    }

    /// What new sprites start with: the saved default, or PICO-8.
    static var newSpriteDefault: Palette { savedDefault ?? .pico8 }

    /// The presets, with the saved default first when there is one.
    static var all: [Palette] { (savedDefault.map { [$0] } ?? []) + presets }

    /// Every distinct visible color used in the sprite's cels, in order of
    /// appearance (Aseprite's "Palette from sprite"), up to `limit`.
    static func colors(in sprite: Sprite, limit: Int = 256) -> [PixelColor] {
        var seen = Set<PixelColor>(), result: [PixelColor] = []
        for frame in sprite.frames {
            for layer in sprite.layers {
                guard let cel = sprite.cel(layer: layer.id, frame: frame.id) else { continue }
                for pixel in cel.pixels where pixel.a != 0 && seen.insert(pixel).inserted {
                    result.append(pixel)
                    if result.count == limit { return result }
                }
            }
        }
        return result
    }
}

/// How palette entries can be ordered (Aseprite's Sort & Gradients menu).
enum PaletteSort: String, CaseIterable, Identifiable, Sendable {
    case hue, saturation, brightness, luminance

    var id: String { rawValue }

    func key(_ color: PixelColor) -> Double {
        switch self {
        case .hue: color.hsv.s < 0.05 ? -1 : color.hsv.h  // grays first
        case .saturation: color.hsv.s
        case .brightness: color.hsv.v
        case .luminance: color.luminance
        }
    }
}

/// Edits on a run of palette entries. Pure functions so they can be tested
/// and undone as one step.
enum PaletteEditing {
    /// Replaces the colors between the first and last entries of `range`
    /// with an even ramp between them (Aseprite's Gradient).
    static func gradient(_ colors: inout [PixelColor], _ range: ClosedRange<Int>) {
        guard range.count > 2, colors.indices.contains(range.lowerBound), colors.indices.contains(range.upperBound) else { return }
        let from = colors[range.lowerBound], to = colors[range.upperBound], steps = Double(range.count - 1)
        for (i, index) in range.enumerated() { colors[index] = from.mixed(with: to, Double(i) / steps) }
    }

    static func reverse(_ colors: inout [PixelColor], _ range: ClosedRange<Int>) {
        guard colors.indices.contains(range.upperBound) else { return }
        colors[range].reverse()
    }

    static func sort(_ colors: inout [PixelColor], _ range: ClosedRange<Int>, by order: PaletteSort, descending: Bool = false) {
        guard colors.indices.contains(range.upperBound) else { return }
        let sorted = colors[range].enumerated().sorted { a, b in
            let ka = order.key(a.element), kb = order.key(b.element)
            if ka == kb { return a.offset < b.offset }  // stable
            return descending ? ka > kb : ka < kb
        }
        colors.replaceSubrange(range, with: sorted.map(\.element))
    }

    /// Moves a run of entries so it starts at `destination`, an index in the
    /// palette as it is now. Returns where the run ends up.
    @discardableResult
    static func move(_ colors: inout [PixelColor], _ range: ClosedRange<Int>, to destination: Int) -> ClosedRange<Int> {
        guard colors.indices.contains(range.upperBound) else { return range }
        let block = Array(colors[range])
        colors.removeSubrange(range)
        let start = min(max(0, destination > range.upperBound ? destination - range.count + 1 : destination), colors.count)
        colors.insert(contentsOf: block, at: start)
        return start...(start + range.count - 1)
    }
}
