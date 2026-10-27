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

While something is selected, drawing, filling and erasing stay inside it, and a bar gives you the common actions: transform, duplicate and move, cut, copy, paste, delete, fill with the primary color, flip, rotate 90°, **arrange**, invert and deselect.

The bar takes the place of the timeline's header, so it never covers the drawing. A switch at its left goes back to the playback controls (a dot on the selection button says the bar is still there) and back again. Deselecting, applying or cancelling brings the header back. With the timeline hidden (collapsed or in focus mode), the bar floats at the bottom of the canvas instead.

While you drag a marquee or the lasso, a label next to it shows the size of the area, counting only the part inside the sprite. Once there's a selection, the bar starts with its size and the position of its top-left corner, like `12×8 · 3, 5`.

**Arrange** (the layers button) brings what's selected to the front, one step forward, one step back or to the back. Each part of a drawing lives on its own layer, so there are two ways:

- **This frame**: only the current frame (or the frames picked in the timeline) changes. The cel gets a **z-index**, as in Aseprite's Cel Properties: it's drawn that many layers higher or lower without moving its layer. An arm can be behind the body in frame 1 and in front of everything in frame 4.
- **Every frame**: the layer moves up or down the stack.

It's also in the transform bar, where it stays part of the transform: **Cancel** puts the order back.

### Selection opacity

With a selection tool (or Move) and something selected, the rail's slider sets the **opacity of the selected pixels**: drag it down to fade them, back up to restore them. It works from the pixels as they were, so you can try values freely, and each drag is one undo step. It changes every layer the selection caught.

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
- the transform bar flips, rotates 90°, **arranges**, **deletes** the floating pixels (also ⌫), **keeps the aspect**, **snaps the angle** to 15° and chooses **RotSprite** (cleaner pixel art) or **fast** rotation.

**Apply** (or tap outside, or ↩) drops the pixels; **Cancel** (⎋) puts everything back. The whole transform is one undo step. With a keyboard, the arrows nudge the pixels 1 px.

### Stretch when moving

Select half a character and move it, and it normally tears away from the rest. Hold **Ctrl** while dragging, as in Aseprite, or turn on **Stretch when moving** in the transform bar (the four-arrow button), and the gap fills with the moved part's trailing edge, so the character grows instead of splitting. Turn it off and the part tears away again. It lasts one transform.

### Transforming several cels

When several cels, layers or frames are selected in the [timeline](./timeline#selecting-a-range), moving, scaling, rotating or flipping changes all of them. A **+N cels** badge in the transform bar tells you how many more change.

## Canvas commands

From the Edit menu: **canvas size** (the canvas shows its edges with handles: drag a side or a corner out to grow it there, in to shrink it; with **In grid cells** the sides land on grid lines, to add whole tiles. The bar shows the new size; **Apply** changes it in one undo step. Drawings, tilemaps, slices and symmetry axes keep their place), **crop to selection**, **trim** empty space, **rotate** and **flip** the whole canvas, and set the **pixel ratio** (for sprites drawn with wide or tall pixels).
