# Gallery and projects

The gallery is the first screen: every sprite you have, with a thumbnail. Animated sprites play in a loop (unless Reduce Motion is on), and a **▶ N** badge tells you how many frames they have.

![The gallery](/screens/en/gallery.jpg)

## Finding a sprite

- **Search** (magnifying glass) filters by name.
- **All / Animations / Still** shows every sprite, only the animated ones, or only single images.
- Touch and hold a sprite to **rename**, **duplicate** or **delete** it.

## A new sprite

Tap **New sprite** (top right) or the dashed card.

<div class="crop-row">

![New sprite](/crops/en/new-sprite.jpg)

</div>

- **Size**: 16, 32, 64, 128 or 256 px, or set width and height up to 1024 px.
- **Background**: transparent, white or black.
- **Starting palette**: DawnBringer 32, PICO-8, Sweetie 16, Endesga 32 and more. You can change it later.

The preview on the right shows what you'll get. Tap **Create** to open the editor.

## Importing

**Import** brings in a file from the Files app:

| File | What you get |
|---|---|
| `.aseprite` / `.ase` | The whole sprite: layers, frames, tags and palette. |
| Animated GIF or PNG | One layer with a frame per frame of the image, keeping each frame's duration. |
| PNG, JPEG | A one-frame sprite (up to 512 × 512 px). |

To bring an image or GIF into a sprite that's already open, use the timeline's layer menu instead: see [Layers](./layers#importing-an-image-or-gif).

## Where sprites are kept

Sprites save on their own, in the background, to **On My iPad › OpenPixel › Sprites** as `.openpixel` files (plain JSON you can read without the app).
