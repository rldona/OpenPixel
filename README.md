# OpenPixel

An **open source** pixel art and animation editor for iPad, built for Apple Pencil.

[Español](README.es.md)

It pairs the clean interface of [Pixaki](https://pixaki.com/) with the working model of [Aseprite](https://www.aseprite.org/docs/): a sprite has **layers** and **frames**, and the image at each layer × frame intersection is a **cel**.

> Status: early (0.1). It covers [Aseprite's Basics](https://www.aseprite.org/docs/basics/) plus tags, drawing tools and a GPU-backed canvas.

## Features

- **Projects** gallery with thumbnails, search, filters (all, animations, still images), rename, duplicate, delete, and PNG/GIF/JPEG import.
- **New sprite**: quick sizes (16–256) or custom up to 1024 px, transparent, white or black background, and a starting palette (PICO-8, Sweetie 16, DawnBringer 16, grays).
- **Editor**
  - Pencil, **spray** (⇧S), eraser, paint bucket, **gradient**, eyedropper, line, **curve**, rectangle, ellipse, **contour** and **polygon** (as in [Aseprite](https://www.aseprite.org/docs/drawing/)).
    - Curve: drag the line, then drag twice to bend each end. Polygon: tap each corner and tap the first one (or Done) to close it. Contour: draw an outline and it fills when you lift. Gradient (⇧G, with the bucket): drag across the area the bucket would fill to blend the primary into the secondary color, linear or radial, smooth or with 2×2, 4×4 or 8×8 Bayer dithering. Control points and corners are marked on the canvas.
  - Floating tool options:
    - square, round or **line** brush (at any angle, in 15° steps) from 1 to 8 px;
    - **custom brush**: select part of the drawing and choose Edit > New brush from selection (⌘B) to paint with it, in its own colors or in the primary color;
    - spray width and speed;
    - optional pixel-perfect for clean 1 px strokes (off by default; the choice is remembered);
    - filled or outlined shapes, previewed while you drag, and rounded rectangle corners;
    - paint bucket: contiguous or global, tolerance, diagonals (8-way spreading) and “All layers” to find the area from every visible layer while painting only the active one;
    - eyedropper: the whole image or the active layer only;
    - when a tool has more options than fit, the bar scrolls sideways.
  - **Symmetry** ([Aseprite's](https://www.aseprite.org/docs/symmetry/)): horizontal, vertical or both. Tap the rail button to turn it on or off; touch and hold to choose the axes or center them. Drag an axis by its handle (below or right of the sprite) to move it in half-pixel steps, so it can run between two pixels or through the middle of one.
  - **Inks** ([Aseprite's](https://www.aseprite.org/docs/ink/)): simple, alpha compositing, copy alpha + color, lock alpha (paint only over what's drawn) and shading (each pass moves drawn pixels to the next or previous palette color). Tool **opacity**, applied once per stroke so going over the same spot doesn't build up.
  - **Apple Pencil pressure** can change the brush size and/or the opacity.
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
- **Aseprite-style timeline**, compact like Aseprite's: drag its top edge to make it taller or shorter (double tap the edge to fit every layer). It keeps the layer you're working on in view, and the tag rows only appear once the sprite has tags.
  - Layers: show/hide, lock, rename, opacity, delete and drag to reorder. The eye, lock and continuity icons in the header act on every layer at once.
  - **Background layer**, as in Aseprite: opaque, underlined, always at the bottom, and erasing or clearing leaves the secondary color. Convert a layer to the background and back from its menu.
  - Frames: “+ Frame” duplicates the current frame; touch and hold for an empty one. Drag a frame number to reorder, delete, and set each frame's duration: −/+, presets up to 4 s, or type any value up to 65 535 ms. Frames that last longer or shorter than most show their duration under the frame number.
  - **Tags**: named, colored frame ranges with a direction (forward, reverse, ping-pong, ping-pong reverse) and a repeat count.
  - **Playback** of the current frame's tag (or all frames) at 0.25× to 3× speed, with first, previous, next and last frame buttons (Home and End on a keyboard).
  - **Linked cels**: cels that share one image, so editing one changes all of them, drawn as one long pill in the timeline. Mark a layer as **continuous** (●● turns into ▬) and new frames link its cel instead of copying it. Unlink from the cel's menu.
  - **Range selection**: tap “Select”, then cels, frame numbers or layer names to select a block, and link, unlink, clear, duplicate, reverse or delete it.
  - **Move and copy blocks** of cels, frames or layers by dragging them, as in Aseprite. A switch next to “Done” chooses between moving and copying. Blocks dropped past the last frame add frames, and copies on a continuous layer are linked to their originals.
  - **Copy and paste between sprites**: copy a block, then paste cels, frames or layers from the menu of a cel, a frame number or a layer in any sprite.
  - **Loop section**, new tags over the selected frames and duration for several frames at once. **Focus a tag band** so playback stays inside its tags.
  - **Cel opacity** (shared by linked cels), duplicate layer, double tap to rename, first frame numbered 0 or 1, and Aseprite's keys: `,` `.` for previous/next frame and ⇧X to show or hide the layer.
  - Configurable **onion skin**: 0–3 frames before and after, opacity, red/blue tint, and an option to stay inside the tag.
- **Smart selection**: with the marquee or lasso, tap a drawn element to select exactly its pixels; its layer becomes active (the topmost visible layer under your finger). Add mode collects several elements. A marquee or lasso takes every visible layer under it (or the layers selected in the timeline) and fits the drawn pixels inside it (switchable with “Fit to content”); over empty canvas it keeps its shape. Moving, transforming, deleting, filling (each layer recolors its own pixels) and cutting that selection changes all those layers; copying copies them merged. Turn on “All frames” to apply all of it to every frame of the animation.
- **Move without switching tools**: with a selection tool, drag inside the selection to move its pixels (with scale and rotate handles); drag outside to select again. **Transforms follow the timeline selection**: with several cels, layers or frames selected in the timeline, moving, scaling, rotating or flipping changes all of them, as in Aseprite.
- **Text tool** (T): tap the canvas and type. Two built-in pixel fonts (5×7 with lowercase and accents, and 3×5 capitals) at whole-pixel scales, or system fonts drawn without smoothing. Letter and line spacing, alignment and a 1 px outline in the secondary color. The text lands as floating pixels you can move, scale or rotate before applying.
- **Color and palettes**, as in Aseprite:
  - Color editor with a spectrum, RGB and HSB sliders, hex, opacity, shades and harmonies (complementary, analogous, triadic…), and a warning with “add to palette” when the color isn't in it.
  - Primary and secondary colors (marked on the palette), swap, and **Replace color** (⇧R) with tolerance, in the current cel or every cel, inside the selection.
  - Palette editing: select a run of colors to edit, gradient, reverse, sort (hue, saturation, brightness, luminance), duplicate, delete and drag to reorder. Everything can be undone.
  - Presets (DawnBringer 32, PICO-8, Sweetie 16, Endesga 32, DawnBringer 16, Game Boy, grays), palette from the sprite's colors, import (.gpl, .hex, .pal, .txt, .png, .gif) and export (.gpl, .hex), and a default palette for new sprites.
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
| `B` / `⇧S` | Pencil / spray |
| `E` | Eraser |
| `G` / `⇧G` | Paint bucket / gradient |
| `I` | Eyedropper |
| `L` / `⇧L` | Line / curve |
| `D` / `⇧D` | Contour / polygon |
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
| `⌘B` | New brush from selection |
| `⇧H` / `⇧V` | Flip horizontally / vertically |
| `↩` / `⎋` / arrows | While transforming: apply / cancel / nudge 1 px |
| `↩` / `⎋` | While building a curve or polygon: done / cancel |
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
