// Writes the manual's demo projects: "Slime", a 32×32 slime on three layers (shadow, body,
// eyes) with an Idle and a Jump tag, eight frames in all, plus three small ones for the
// gallery ("Coin", "Heart", "Tree"), all in the PICO-8 palette.
// Run from manual/: swift scripts/make-demo.swift <folder>
// and copy the .openpixel files into the app's Documents/Sprites (simulator or Files).
import Foundation

let size = 32
let palette = ["#000000", "#1D2B53", "#7E2553", "#008751", "#AB5236", "#5F574F", "#C2C3C7", "#FFF1E8",
               "#FF004D", "#FFA300", "#FFEC27", "#00E436", "#29ADFF", "#83769C", "#FF77A8", "#FFCCAA"]

typealias RGBA = (UInt8, UInt8, UInt8, UInt8)
func color(_ hex: String) -> RGBA {
    let v = UInt32(hex.dropFirst(), radix: 16)!
    return (UInt8(v >> 16 & 255), UInt8(v >> 8 & 255), UInt8(v & 255), 255)
}
let outline = color("#1D2B53"), body = color("#00E436"), shade = color("#008751"), light = color("#FFF1E8")
let eye = color("#1D2B53"), shadow = color("#5F574F")

struct Image {
    var pixels = [UInt8](repeating: 0, count: size * size * 4)
    mutating func set(_ x: Int, _ y: Int, _ c: RGBA) {
        guard x >= 0, y >= 0, x < size, y < size else { return }
        let i = (y * size + x) * 4
        pixels[i] = c.0; pixels[i + 1] = c.1; pixels[i + 2] = c.2; pixels[i + 3] = c.3
    }
    var base64: String { Data(pixels).base64EncodedString() }
}

/// Inside an ellipse centred on (cx, cy), measured at pixel centres.
func inside(_ x: Int, _ y: Int, cx: Double, cy: Double, rx: Double, ry: Double) -> Bool {
    let dx = (Double(x) + 0.5 - cx) / rx, dy = (Double(y) + 0.5 - cy) / ry
    return dx * dx + dy * dy <= 1
}

/// One pose: how wide and tall the body is and how high it floats.
struct Pose { let rx: Double; let ry: Double; let lift: Double }
let poses = [
    // Idle: a slow squash and stretch on the ground.
    Pose(rx: 10, ry: 8, lift: 0), Pose(rx: 10.5, ry: 7.5, lift: 0), Pose(rx: 11, ry: 7, lift: 0), Pose(rx: 10.5, ry: 7.5, lift: 0),
    // Jump: crouch, take off, top, land.
    Pose(rx: 12, ry: 6, lift: 0), Pose(rx: 8.5, ry: 9.5, lift: 6), Pose(rx: 9.5, ry: 8.5, lift: 10), Pose(rx: 11.5, ry: 6.5, lift: 0),
]
let ground = 27.0

var frames: [[String: Any]] = []
var cels: [[String: Any]] = []
let layerIDs = (shadow: UUID().uuidString, body: UUID().uuidString, eyes: UUID().uuidString)

for (index, pose) in poses.enumerated() {
    let frameID = UUID().uuidString
    frames.append(["id": frameID, "duration": index < 4 ? 150 : 100])
    let cx = 16.0, cy = ground - pose.ry - pose.lift

    var shadowImage = Image()
    let shadowWidth = max(3, pose.rx * 0.8 - pose.lift * 0.4)
    for y in 0..<size { for x in 0..<size where inside(x, y, cx: cx, cy: ground + 0.5, rx: shadowWidth, ry: 1.6) { shadowImage.set(x, y, shadow) } }

    var bodyImage = Image()
    for y in 0..<size {
        for x in 0..<size where inside(x, y, cx: cx, cy: cy, rx: pose.rx, ry: pose.ry) {
            let edge = !inside(x, y, cx: cx, cy: cy, rx: pose.rx - 1, ry: pose.ry - 1)
            let lower = Double(y) + 0.5 > cy + pose.ry * 0.45
            bodyImage.set(x, y, edge ? outline : (lower ? shade : body))
        }
    }
    // A highlight on the upper left.
    let hx = Int(cx - pose.rx * 0.5), hy = Int(cy - pose.ry * 0.5)
    bodyImage.set(hx, hy, light); bodyImage.set(hx + 1, hy, light); bodyImage.set(hx, hy + 1, light)

    var eyesImage = Image()
    let ey = Int(cy - pose.ry * 0.1)
    for ex in [Int(cx) - 4, Int(cx) + 3] {
        eyesImage.set(ex, ey, eye); eyesImage.set(ex, ey + 1, eye)
        if index == 6 { eyesImage.set(ex, ey + 1, (0, 0, 0, 0)) } // a blink at the top of the jump
    }

    for (layer, image) in [(layerIDs.shadow, shadowImage), (layerIDs.body, bodyImage), (layerIDs.eyes, eyesImage)] {
        cels.append(["layer": layer, "frame": frameID, "image": ["width": size, "height": size, "rgba": image.base64]])
    }
}

func layer(_ id: String, _ name: String) -> [String: Any] {
    ["id": id, "name": name, "isVisible": true, "isLocked": false, "opacity": 1, "isContinuous": false,
     "isBackground": false, "isGroup": false, "isExpanded": true, "blendMode": "normal"]
}

let sprite: [String: Any] = [
    "width": size, "height": size, "colorMode": "rgba", "palette": palette,
    "layers": [layer(layerIDs.shadow, "Shadow"), layer(layerIDs.body, "Body"), layer(layerIDs.eyes, "Eyes")],
    "frames": frames, "cels": cels,
    "tags": [
        ["id": UUID().uuidString, "name": "Idle", "from": 0, "to": 3, "color": "#29ADFF", "direction": "forward", "repeatCount": 0],
        ["id": UUID().uuidString, "name": "Jump", "from": 4, "to": 7, "color": "#FF77A8", "direction": "forward", "repeatCount": 0],
    ],
    "links": [], "celOpacity": [], "slices": [], "tilemaps": [],
    "grid": ["width": 16, "height": 16, "offsetX": 0, "offsetY": 0],
    "pixelRatio": ["width": 1, "height": 1],
]

let folder = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
func write(_ name: String, _ sprite: [String: Any]) throws {
    let file = folder.appendingPathComponent("\(UUID().uuidString).openpixel")
    try JSONSerialization.data(withJSONObject: ["name": name, "version": 1, "sprite": sprite]).write(to: file)
    print(file.path)
}

/// A one-layer sprite whose frames are drawn by `draw(frame, x, y)`.
func simple(width: Int, height: Int, frames count: Int, duration: Int = 100, draw: (Int, Int, Int) -> RGBA?) -> [String: Any] {
    let layerID = UUID().uuidString
    var frames: [[String: Any]] = [], cels: [[String: Any]] = []
    for f in 0..<count {
        let id = UUID().uuidString
        frames.append(["id": id, "duration": duration])
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height { for x in 0..<width { if let c = draw(f, x, y) {
            let i = (y * width + x) * 4
            pixels[i] = c.0; pixels[i + 1] = c.1; pixels[i + 2] = c.2; pixels[i + 3] = c.3
        } } }
        cels.append(["layer": layerID, "frame": id, "image": ["width": width, "height": height, "rgba": Data(pixels).base64EncodedString()]])
    }
    return ["width": width, "height": height, "colorMode": "rgba", "palette": palette,
            "layers": [layer(layerID, "Layer 1")], "frames": frames, "cels": cels, "tags": [],
            "links": [], "celOpacity": [], "slices": [], "tilemaps": [],
            "grid": ["width": 16, "height": 16, "offsetX": 0, "offsetY": 0], "pixelRatio": ["width": 1, "height": 1]]
}

try write("Slime", sprite)

// A coin turning: its width shrinks to an edge and grows back.
let gold = color("#FFA300"), yellow = color("#FFEC27"), brown = color("#AB5236")
try write("Coin", simple(width: 16, height: 16, frames: 6) { f, x, y in
    let widths = [6.5, 5, 3, 1.2, 3, 5]
    let rx = widths[f]
    guard inside(x, y, cx: 8, cy: 8, rx: rx, ry: 6.5) else { return nil }
    if !inside(x, y, cx: 8, cy: 8, rx: rx - 1, ry: 5.5) { return brown }
    return x < 8 && rx > 2 ? yellow : gold
})

// A heart.
let red = color("#FF004D"), pink = color("#FF77A8"), dark = color("#7E2553")
let heart = ["..XX...XX..", ".XooX.XooX.", "XwooooXoooX", "XwooooooooX", "XoooooooooX", ".XoooooooX.",
             "..XoooooX..", "...XoooX...", "....XoX....", ".....X....."]
try write("Heart", simple(width: 16, height: 16, frames: 1) { _, x, y in
    let row = y - 3, column = x - 2
    guard row >= 0, row < heart.count, column >= 0, column < heart[row].count else { return nil }
    switch Array(heart[row])[column] {
    case "X": return dark
    case "o": return red
    case "w": return pink
    default: return nil
    }
})

// A round tree on a trunk.
let leaf = color("#008751"), leafLight = color("#00E436"), trunk = color("#AB5236"), trunkDark = color("#5F574F")
try write("Tree", simple(width: 32, height: 32, frames: 1) { _, x, y in
    if inside(x, y, cx: 16, cy: 12, rx: 11, ry: 10) {
        if !inside(x, y, cx: 16, cy: 12, rx: 10, ry: 9) { return outline }
        return inside(x, y, cx: 13, cy: 9, rx: 5, ry: 4) ? leafLight : leaf
    }
    if x >= 14, x <= 18, y >= 21, y <= 29 { return x == 14 || x == 18 ? trunkDark : trunk }
    return nil
})
