# Getting started

OpenPixel is an open source pixel art and animation editor for iPad, built for the Apple Pencil. It pairs the clean interface of [Pixaki](https://pixaki.com/) with the working model of [Aseprite](https://www.aseprite.org/docs/): a sprite has **layers** and **frames**, and the image where a layer and a frame meet is a **cel**.

![The OpenPixel editor](/screens/en/editor.jpg)

## What you see

| Area | What it does |
|---|---|
| **Top bar** | Back to the gallery, the active tool's options in the middle, and on the right the Edit menu (…), focus mode, grid, tiled mode and **Export**. |
| **Tool rail** (left) | Drawing tools, selection, move, symmetry, scripts, and undo and redo at the bottom. See [Drawing tools](./drawing). |
| **Canvas** (centre) | Where you draw. Pinch to zoom, drag with two fingers to pan. |
| **Side panel** (right) | The animated preview, zoom buttons, the palette, the color selector and quick color actions. See [Color and palettes](./color). |
| **Timeline** (bottom) | Playback, frames, tags and layers. See [Layers](./layers) and [Frames and animation](./timeline). |

## Your first sprite in five steps

1. In the gallery, tap **New sprite**, pick a size (16 to 256, or custom up to 1024 px), a background and a starting palette, and tap **Create**. See [Gallery and projects](./gallery).
2. Draw with the Apple Pencil. Touch and hold the canvas with a finger to pick a color, or tap one in the palette.
3. Tap **+ Frame** in the timeline to copy the frame and draw the next pose. Turn on **Onion skin** to see the frames around it.
4. Tap **▶** to play, or watch the preview in the side panel while you draw.
5. Tap **Export** and choose PNG, GIF, sprite sheet or Aseprite. See [Export](./export).

::: tip Everything saves on its own
Sprites are saved automatically, in the background, to `Documents/Sprites` (visible in the Files app) as readable `.openpixel` files.
:::

## A quick vocabulary

- **Sprite**: one drawing or animation, with its size and palette.
- **Layer**: a sheet stacked on the others, like an outline over its colors.
- **Frame**: one step of the animation, with its own duration in milliseconds.
- **Cel**: what one layer shows in one frame.
- **Tag**: a named range of frames (Idle, Run…) that plays on its own.
