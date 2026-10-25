# Tilemaps

A **tilemap layer** is drawn with tiles, as in [Aseprite](https://www.aseprite.org/docs/tilemap/): a grid of cells, each showing one tile from the layer's **tileset**. Change a tile and every cell that uses it changes.

## Creating one

- From the timeline's **+** menu, **New tilemap layer**: its tiles take the size of the grid's cells (set the grid by touching and holding **#**).
- Or convert an existing layer from its menu, **Convert to tilemap**. **Convert to normal layer** turns it back.

While a tilemap layer is active, the side panel shows **Palette | Tileset** tabs in the palette's place, and opens on **Tileset**.

## Pixels or tiles

The switch at the top of the tileset chooses what you draw.

### Pixels

You paint pixels as usual, and the tileset mode decides what happens to the tiles:

| Mode | What an edit does |
|---|---|
| **Manual** | Editing a cell edits its tile, so every copy changes. |
| **Auto** | Each edited cell gets a matching tile, new or reused; tiles nobody uses go away. |
| **Stack** | Each edit makes a new tile. |

### Tiles

Pick a tile in the tileset and place it:

- the **pencil** places the selected tile;
- the **eraser** clears cells;
- the **bucket** fills connected cells;
- the **eyedropper** picks the tile under your finger.

## Exporting the tileset

The share button next to the tileset exports it as a PNG strip.
