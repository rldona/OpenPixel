# Selection and transform

## Selecting

The selection slot in the rail holds four tools, as in [Aseprite](https://www.aseprite.org/docs/selecting/):

| Tool | Key | How it selects |
|---|---|---|
| Rectangular marquee | M | Drag a rectangle. |
| Elliptical marquee | ⇧M | Drag an ellipse. |
| Lasso | Q | Draw around the area. |
| Magic wand | W | Tap a color: with a tolerance, contiguous or not, from the current layer or all layers. |

The options bar picks the mode: **replace**, **add**, **subtract** or **intersect** (instead of Shift and Alt on a computer).

![A selection with its action bar](/crops/en/selection.jpg)

While something is selected, drawing, filling and erasing stay inside it, and a floating bar gives you the common actions: transform, duplicate and move, cut, copy, paste, delete, fill with the primary color, flip, rotate 90°, invert and deselect.

### Smart selection

- **Tap a drawn element** with the marquee or lasso to select exactly its pixels. Its layer becomes active (the topmost visible layer under your finger). In add mode, keep tapping to collect several elements.
- A marquee or lasso takes **every visible layer** under it (or the layers selected in the timeline) and, with **Fit to content**, shrinks to the drawn pixels inside it. Over empty canvas it keeps its shape.
- Moving, transforming, deleting, filling and cutting that selection changes all those layers. Copying copies them merged.
- **All frames** applies all of it to every frame of the animation.

### More selection commands

From the Edit menu (…): **select all** (⌘A), **deselect** (⌘D), **reselect** (⇧⌘D), **invert** (⇧⌘I), **select layer content**, and **expand**, **contract** or **border** by a number of pixels.

## Moving and transforming

With a selection tool, **drag inside the selection** to move its pixels; drag outside to select again. The Move tool (V) moves the whole cel, or the selection if there is one.

![Moving with the transform bar](/crops/en/stretch.jpg)

While pixels are floating, the canvas shows handles:

- drag the **corners and edges** to scale (drag past the opposite edge to flip);
- drag the **round handle** above to rotate around the **pivot** (the dot in the middle, which you can drag);
- the transform bar flips, rotates 90°, **keeps the aspect**, **snaps the angle** to 15° and chooses **RotSprite** (cleaner pixel art) or **fast** rotation.

**Apply** (or tap outside, or ↩) drops the pixels; **Cancel** (⎋) puts everything back. The whole transform is one undo step. With a keyboard, the arrows nudge the pixels 1 px.

### Stretch when moving

Select half a character and move it, and it normally tears away from the rest. Hold **Ctrl** while dragging, as in Aseprite, or turn on **Stretch when moving** in the transform bar (the four-arrow button), and the gap fills with the moved part's trailing edge, so the character grows instead of splitting. Turn it off and the part tears away again. It lasts one transform.

### Transforming several cels

When several cels, layers or frames are selected in the [timeline](./timeline#selecting-a-range), moving, scaling, rotating or flipping changes all of them. A **+N cels** badge in the transform bar tells you how many more change.

## Canvas commands

From the Edit menu: **crop to selection**, **trim** empty space, **rotate** and **flip** the whole canvas, and set the **pixel ratio** (for sprites drawn with wide or tall pixels).
