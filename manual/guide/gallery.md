# Gallery and projects

The gallery is the first screen: every sprite you have, with a thumbnail. Animated sprites play in a loop (unless Reduce Motion is on), and a **▶ N** badge tells you how many frames they have.

![The gallery](/screens/en/gallery.jpg)

## Finding a sprite

- **Search** (magnifying glass) filters by name.
- **All / Animations / Still** shows every sprite, only the animated ones, or only single images.
- Touch and hold a sprite to **rename**, **duplicate**, **export** or **delete** it. **Export** opens the same [export](./export) window as the editor, without opening the sprite.

## Folders

Keep projects together in folders, one level deep:

- Tap the **folder** button at the top to make an empty one, or touch and hold a project and choose **Move to folder › New folder…**.
- Put a project in a folder by dragging it onto the folder, or with **Move to folder**. Inside a folder, drag a project onto **‹ Projects** (or choose **Remove from folder**) to take it out.
- Tap a folder to open it. New sprites and imports made there go in it, and duplicates stay with the original.
- Touch and hold a folder to **rename** or **delete** it. Deleting a folder keeps its projects: they go back to the home screen.
- Search looks in every folder.

## A new sprite

Tap **New sprite** (top right) or the dashed card.

<div class="crop-row">

![New sprite](/crops/en/new-sprite.jpg)

</div>

- **Size**: 16, 32, 64, 128 or 256 px, or set width and height up to 1024 px.
- **Background**: transparent, white or black.
- **Starting palette**: DawnBringer 32, PICO-8, Sweetie 16, Endesga 32 and more, or **Empty** to build your own. You can change it later.

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
