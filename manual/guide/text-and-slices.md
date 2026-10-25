# Text and slices

## Text

The **text tool** (T) writes pixel text:

1. Tap the canvas where the text goes and type.
2. Choose the font in the options bar: two built-in pixel fonts (5×7 with lowercase and accents, and 3×5 capitals) at whole-pixel scales, or a system font drawn without smoothing.
3. Set the **letter** and **line spacing**, the **alignment**, and an optional **1 px outline** in the secondary color.

The text lands as floating pixels you can move, scale or rotate, like any [transform](./selection#moving-and-transforming), before you apply it.

## Slices

A **slice** is a named, colored rectangle over part of the sprite, as in [Aseprite](https://www.aseprite.org/docs/slices/), for game engines: a button with stretchable edges, a hit box, a pivot point.

- The slice tool (⇧C) shares a slot with Move. Drag to draw a slice.
- Drag inside a slice to move it, or drag an edge or corner to resize it. Tap another slice to pick it.
- Its properties set the name, color, a **9-slice center** (the part that stretches) and a **pivot**.
- Changing a slice on a later frame adds a key there, so slices can follow the animation.

Slices are exported as one PNG each, or listed in a sprite sheet's JSON. See [Export](./export).
