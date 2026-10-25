# Color and palettes

Color lives in the side panel, as in Aseprite: the palette at the top, the color selector below it and the color actions under that.

<div class="crop-row">

![The palette and color selector](/crops/en/color-panel.jpg)

</div>

## Primary and secondary colors

You always have two colors. The **primary** paints; the **secondary** is what the eraser leaves on a background layer, the end of a gradient and the text outline.

The two **chips** under the selector show them with their hex value:

- The chip with the accent border is the one the square and bars edit. Tap the other chip to edit it instead.
- Tap the active chip's swatch to open the full **color editor**.
- Tap the hex value to type one; it applies when you press return.
- A **!** badge on a swatch means that color isn't in the palette. Tap it to add it.
- **Swap** (X) exchanges the two colors. The Apple Pencil Pro **squeeze** does the same.

## The color selector

Always on, under the palette:

- the **square** sets saturation (left to right) and brightness (bottom to top);
- the **hue** bar picks the hue;
- the **opacity** bar sets the transparency.

Drag and the pencil already paints with the new color. Picking a color from the palette or with the eyedropper moves the handles to it, so it's easy to find a slightly lighter or darker shade.

## The color editor

Tapping the active chip's swatch opens the full editor: a spectrum, **RGB** and **HSB** sliders, the hex value, opacity, **shades** of the current color and **harmonies** (complementary, analogous, triadic, split complementary, tetradic). The left half of the swatch at the top is the color you started with: tap it to go back.

## The palette

Tap a color to make it the primary. The primary and secondary colors are marked on the palette.

- **Edit colors** turns on palette editing: select a run of colors to edit one, make a **gradient** between the ends, **reverse**, **sort** (by hue, saturation, brightness or luminance), **duplicate**, **delete**, or drag to reorder. Everything can be undone.
- The **…** menu loads a preset (DawnBringer 32, PICO-8, Sweetie 16, Endesga 32, DawnBringer 16, Game Boy, grays…), makes a palette from the sprite's colors, imports one (`.gpl`, `.hex`, `.pal`, `.txt`, `.png`, `.gif`), exports it (`.gpl`, `.hex`) or sets the default palette for new sprites. Palettes from installed [extensions](./scripts) are listed there too.

## Color actions

| Button | What it does |
|---|---|
| **Swap** | Exchanges the primary and secondary colors. |
| **Replace…** (⇧R) | Replaces one color with another, with a tolerance, in the current cel or every cel, and only inside the selection if there is one. |
| **Hue/Saturation** | A floating window to shift hue, saturation, lightness (or value) and alpha, or the R, G, B and A channels, in the current cel or every cel, previewed live. **Apply** keeps it, **Cancel** goes back. The canvas can still be moved and zoomed while it's open, but not painted. |
| **Color shading** | A floating window with ramps of the primary color, lighter and darker. Tap a shade to paint with it; touch and hold it to use it as the secondary color or add it to the palette. |

Only one of the two windows is open at a time: opening one closes the other.
