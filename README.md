# OpenPixel

An **open source** pixel art and animation editor for iPad, built for Apple Pencil.

[Español](README.es.md)

It pairs the clean interface of [Pixaki](https://pixaki.com/) with the working model of [Aseprite](https://www.aseprite.org/docs/): a sprite has **layers** and **frames**, and the image at each layer × frame intersection is a **cel**.

> Status: early (0.1). It covers [Aseprite's Basics](https://www.aseprite.org/docs/basics/) plus tags, drawing tools and a GPU-backed canvas.

## Features

- **Projects** gallery with thumbnails, search, filters (all, animations, still images), rename, duplicate, delete, and PNG/GIF/JPEG import.
- **New sprite**: quick sizes (16–256) or custom up to 1024 px, transparent, white or black background, and a starting palette (PICO-8, Sweetie 16, DawnBringer 16, grays).
- **Editor**
  - Pencil, eraser, paint bucket, eyedropper, line, rectangle and ellipse, plus horizontal symmetry.
  - Floating tool options:
    - square or round brush from 1 to 8 px;
    - pixel-perfect for clean 1 px strokes;
    - filled or outlined shapes, previewed while you drag;
    - contiguous or global fill.
  - Pixel grid, whole-number zoom levels and fit to screen.
- **Selection** (as in [Aseprite](https://www.aseprite.org/docs/selecting/))
  - Rectangular and elliptical marquee, lasso and magic wand (tolerance, contiguous, current layer or all layers).
  - Replace, add, subtract and intersect modes, chosen in the tool options instead of Shift/Alt.
  - Select all, deselect, reselect, invert, select layer content, and expand, contract or border.
  - Marching ants. Drawing, filling and erasing stay inside the selection.
  - Cut, copy, paste (also images from other apps), delete and fill with the primary color.
- **Transform** (as in [Aseprite](https://www.aseprite.org/docs/transformations/))
  - Move, scale (drag past an edge to flip), rotate around a movable pivot, with RotSprite or fast rotation, keep aspect and 15° angle snapping.
  - Flip and rotate 90° the selection or, with nothing selected, the whole cel. Duplicate and move.
  - Apply, cancel, or tap outside to apply. The whole transform is one undo step.
  - Canvas: crop to selection, trim empty space, rotate and flip.
  - Undo and redo (up to 100 steps).
- **Aseprite-style timeline**
  - Layers: show/hide, lock, rename, opacity, delete and drag to reorder.
  - Frames: “+ Frame” duplicates the current frame; touch and hold for an empty one. Drag a frame number to reorder, delete, and set each frame's duration in ms.
  - **Tags**: named, colored frame ranges with a direction (forward, reverse, ping-pong, ping-pong reverse) and a repeat count.
  - **Playback** of the current frame's tag (or all frames) at 0.25× to 3× speed.
  - **Linked cels**: cels that share one image, so editing one changes all of them, joined by a line in the timeline. Mark a layer as **continuous** (chain icon) and new frames link its cel instead of copying it. Unlink from the cel's menu.
  - **Range selection**: tap “Select”, then cels or frame numbers to select a block, and link, unlink, clear, duplicate, reverse or delete it.
  - Configurable **onion skin**: 0–3 frames before and after, opacity, red/blue tint, and an option to stay inside the tag.
- **Color**: primary and secondary colors, the system color picker and an editable palette.
- **Export**: PNG of the current frame, sprite sheet or animated GIF, at 1×–10× with nearest-neighbor scaling. Sprite sheets and GIFs can be limited to one tag, and GIFs follow the tag's direction and repeat count. Files are shared through the iOS share sheet.
- **Autosave** to `Documents/Sprites` (visible in the Files app), as readable `.openpixel` JSON. Saving runs in the background.
- **Preferences**: English (default) or Spanish, and light, dark or system appearance.
- Full-screen editing with no status bar, and a focus mode that leaves only the canvas.

## Performance

Drawing stays smooth on large canvases (256×256 and up):

- the canvas is made of Core Animation layers, so zooming and panning are done by the GPU;
- while you draw, only the pixels a stroke touched are recomposited, and the rest of the UI updates once, when the stroke ends;
- all Apple Pencil samples of a touch event are processed as one batch.

`PerformanceTests` prints the cost per Pencil event. Profile **Release** builds: unoptimized Debug builds are about 100× slower in the pixel loops.

## Gestures

| Gesture | Action |
|---|---|
| Apple Pencil | Draw with the current tool |
| One finger | Draws until the Pencil is used; after that, fingers only navigate |
| Pinch / two fingers | Zoom and pan |
| Two-finger tap | Undo |
| Three-finger tap | Redo |
| Touch and hold (with Pencil) | Quick eyedropper |
| Double-tap on the Pencil | Toggle eraser and previous tool |
| Four-finger tap | Focus mode: hide or show the panels |

With a keyboard, OpenPixel uses Aseprite's shortcuts:

| Key | Action |
|---|---|
| `B` | Pencil |
| `E` | Eraser |
| `G` | Paint bucket |
| `I` | Eyedropper |
| `L` | Line |
| `U` / `⇧U` | Rectangle / ellipse |
| `[` `]` | Brush size |
| `M` / `⇧M` | Rectangular / elliptical marquee |
| `Q` | Lasso |
| `W` | Magic wand |
| `V` | Move |
| `⌘A` / `⌘D` / `⇧⌘D` | Select all / deselect / reselect |
| `⇧⌘I` | Invert selection |
| `⌘X` `⌘C` `⌘V` | Cut, copy, paste |
| `⌘T` | Transform |
| `⇧H` / `⇧V` | Flip horizontally / vertically |
| `↩` / `⎋` / arrows | While transforming: apply / cancel / nudge 1 px |
| `X` | Swap colors |
| `⌥N` | New frame (duplicates the current one) |
| `⌥⇧N` | New empty frame |
| `⇧N` | New layer |
| `⌥⌘T` | New tag |
| `↩` | Play |
| `←` `→` | Previous / next frame |
| `⌘Z` / `⇧⌘Z` | Undo / redo |
| `⇥` (Tab) | Focus mode |

## Building

Requirements: Xcode 16 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen), iPadOS 17 or later.

```bash
brew install xcodegen
cp Config/Local.xcconfig.example Config/Local.xcconfig   # set your DEVELOPMENT_TEAM
xcodegen generate
open OpenPixel.xcodeproj
```

`OpenPixel.xcodeproj` is generated from `project.yml` and isn't committed.

Tests:

```bash
xcodebuild test -project OpenPixel.xcodeproj -scheme OpenPixel -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'
```

## Project layout

```
OpenPixel/
  App/         Entry point, theme, preferences
  Model/       Sprite, layers, frames, cels, tags, colors, palettes, rasterization
  Document/    SpriteDocument (editing state + undo) and storage
  Rendering/   CGImage conversion and PNG/GIF export
  Views/       Gallery, new sprite, editor (UIKit canvas, timeline, panel), export, preferences
  Resources/   Assets and localizations (en, es)
OpenPixelTests/
```

## Contributing

Contributions are welcome. Please write code, comments, commit messages, issues and pull requests in **English**.

- Any new UI text uses an English key. Add its Spanish translation to `OpenPixel/Resources/es.lproj/Localizable.strings`.
- Run the tests before opening a pull request.

## Roadmap

- Indexed and grayscale color modes
- Opening and saving `.aseprite` files

## License

[MIT](LICENSE)
