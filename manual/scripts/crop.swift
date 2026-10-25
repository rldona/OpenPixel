// Turns raw simulator screenshots (manual/raw/<lang>/*.png, 2420x1668) into the manual's images:
// full screens and crops of single features, as JPEG. OpenPixel hides the status bar, so full
// screens are kept whole.
// Run from manual/: swift scripts/crop.swift
//
// Boxes are (x, y, width, height) measured on a 2000-pixel-wide view of the screenshot;
// they're scaled to the real 2420 pixels here.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let scale = 2420.0 / 2000.0

let crops: [String: [(name: String, box: CGRect?)]] = [
    "gallery": [("gallery", nil)],
    "new-sprite": [("new-sprite", CGRect(x: 360, y: 96, width: 680, height: 770))],
    "editor": [
        ("editor", nil),
        ("tool-rail", CGRect(x: 0, y: 96, width: 112, height: 1240)),
        ("top-bar", CGRect(x: 0, y: 0, width: 2000, height: 92)),
        ("timeline", CGRect(x: 112, y: 1062, width: 1426, height: 317)),
        ("color-panel", CGRect(x: 1545, y: 440, width: 455, height: 760)),
    ],
    "edit-menu": [("edit-menu", CGRect(x: 1290, y: 10, width: 420, height: 870))],
    "pencil-menu": [("pencil-menu", CGRect(x: 0, y: 96, width: 410, height: 300))],
    "selection": [("selection", CGRect(x: 200, y: 100, width: 1260, height: 930))],
    "stretch": [("stretch", CGRect(x: 200, y: 100, width: 1260, height: 930))],
    "export": [("export", CGRect(x: 520, y: 140, width: 960, height: 1095))],
    "export-sheet": [("export-sheet", CGRect(x: 520, y: 140, width: 960, height: 1095))],
    "layer-menu": [("layer-menu", CGRect(x: 80, y: 360, width: 420, height: 980))],
    "new-layer-menu": [("new-layer-menu", CGRect(x: 498, y: 680, width: 380, height: 540))],
    "onion": [("onion", CGRect(x: 340, y: 100, width: 1000, height: 1279))],
    "scripts-menu": [("scripts-menu", CGRect(x: 0, y: 490, width: 410, height: 340))],
    "script-dialog": [("script-dialog", CGRect(x: 1066, y: 110, width: 454, height: 1222))],
    "preferences": [("preferences", CGRect(x: 520, y: 140, width: 960, height: 1095))],
]

func load(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func saveJPEG(_ image: CGImage, maxWidth: Int, to path: String) {
    let w = min(maxWidth, image.width)
    let h = Int((Double(image.height) * Double(w) / Double(image.width)).rounded())
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary)
    CGImageDestinationFinalize(dest)
}

for lang in ["en", "es"] {
    for (raw, outs) in crops {
        guard let image = load("raw/\(lang)/\(raw).png") else { print("missing", lang, raw); continue }
        for (name, box) in outs {
            let kind = box == nil ? "screens" : "crops"
            let dir = "public/\(kind)/\(lang)"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let b = box ?? CGRect(x: 0, y: 0, width: 2000, height: 1379)
            let px = CGRect(x: b.minX * scale, y: b.minY * scale, width: b.width * scale, height: b.height * scale)
                .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let cut = image.cropping(to: px) else { print("bad box", raw, name); continue }
            saveJPEG(cut, maxWidth: kind == "screens" ? 1600 : 1000, to: "\(dir)/\(name).jpg")
        }
    }
}
print("done")
