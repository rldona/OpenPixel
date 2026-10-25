# Frames and animation

The timeline at the bottom holds the frames (numbered across the top), the tags above them and a cel for every layer and frame.

![The timeline](/crops/en/timeline.jpg)

## The timeline's size

Drag the **grab bar** on its top edge to make it taller or shorter; double tap it to fit every layer. Keep pushing down and it hides behind a small capsule with play, the frame number and a scrubber. Tap its arrow or drag it up to bring the timeline back.

Past the last frame and the last layer, faint **projected** frames and layers keep the grid going. Tap one to create everything up to it in one step.

## Frames

- **+ Frame** (⌥N) duplicates the current frame; touch and hold it for an empty one (⌥⇧N).
- The **bin** deletes the current frame.
- Drag a frame number to reorder it. Touch and hold it for its menu.
- The **duration** (100 ms ⌄) sets how long the current frame lasts: −/+, presets up to 4 s, or type any value up to 65 535 ms. Frames that last longer or shorter than most show their duration under the number.
- `,` and `.` (or ← and →) go to the previous and next frame; Home and End to the first and last.

## Playback

**▶** (↩) plays the current frame's tag, or every frame if it has none. **1× ⌄** sets the speed, from 0.25× to 3×. The buttons around play go to the first, previous, next and last frame. The side panel's **preview** has its own play button, so the animation keeps running while you draw.

## Tags

A **tag** is a named, colored range of frames, such as *Idle* or *Jump*. Tap **Tag** (⌥⌘T) to make one over the current frame or the selected frames. Each tag has:

- a **direction**: forward, reverse, ping-pong or ping-pong reverse;
- a **repeat** count (0 loops forever).

Tap a tag to edit it. Overlapping tags go in separate **bands**; **focus a band** so playback stays inside its tags.

## Onion skin

**Onion skin** shows the frames before and after the current one, faded, so you can follow the motion. Tap it to turn it on; touch and hold it for its settings:

![Onion skin on](/crops/en/onion.jpg)

- **Previous** and **next frames**: 0 to 3 each way;
- **opacity**;
- **tint**: red before, blue after;
- **only inside the tag**.

## Linked cels

**Linked cels** share one image: editing one changes all of them. They're drawn as one long pill in the timeline.

- Mark a layer as **continuous** (its ●● turns into ▬) and new frames link its cel instead of copying it.
- Link or unlink cels from a cel's menu or a range selection.

A cel's menu also sets its **opacity** (shared by linked cels).

## Selecting a range

Tap **Select**, then cels, frame numbers or layer names to select a block. With it you can **link**, **unlink**, **clear**, **duplicate**, **reverse** or **delete** it, make a **tag** over its frames, set the **duration** of several frames at once, and **loop** that section.

- **Move and copy blocks** of cels, frames or layers by dragging them. A switch next to **Done** chooses between moving and copying. Blocks dropped past the last frame add frames.
- **Copy and paste between sprites**: copy a block, then paste cels, frames or layers from the menu of a cel, a frame number or a layer in any sprite.
- [Transforms](./selection#transforming-several-cels) change every selected cel.
