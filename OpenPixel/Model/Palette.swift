import Foundation

struct Palette: Identifiable, Hashable {
    let name: String
    let colors: [PixelColor]
    var id: String { name }

    private init(_ name: String, _ hexes: [String]) {
        self.name = name
        self.colors = hexes.compactMap(PixelColor.init(hex:))
    }

    static let pico8 = Palette("PICO-8", [
        "#000000", "#1D2B53", "#7E2553", "#008751", "#AB5236", "#5F574F", "#C2C3C7", "#FFF1E8",
        "#FF004D", "#FFA300", "#FFEC27", "#00E436", "#29ADFF", "#83769C", "#FF77A8", "#FFCCAA"
    ])

    static let sweetie16 = Palette("Sweetie 16", [
        "#1A1C2C", "#5D275D", "#B13E53", "#EF7D57", "#FFCD75", "#A7F070", "#38B764", "#257179",
        "#29366F", "#3B5DC9", "#41A6F6", "#73EFF7", "#F4F4F4", "#94B0C2", "#566C86", "#333C57"
    ])

    static let db16 = Palette("DawnBringer 16", [
        "#140C1C", "#442434", "#30346D", "#4E4A4E", "#854C30", "#346524", "#D04648", "#757161",
        "#597DCE", "#D27D2C", "#8595A1", "#6DAA2C", "#D2AA99", "#6DC2CA", "#DAD45E", "#DEEED6"
    ])

    static let grays = Palette("Grays", (0..<16).map { i in
        let v = i * 17
        return String(format: "#%02X%02X%02X", v, v, v)
    })

    static let all: [Palette] = [.pico8, .sweetie16, .db16, .grays]
}
