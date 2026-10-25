# OpenPixel user manual

The bilingual user guide (English at the root, Spanish under `es/`), built with [VitePress](https://vitepress.dev) and published to <https://rldona.github.io/OpenPixel/> by `.github/workflows/manual.yml` on every push to `main` that touches this folder.

```bash
npm install
npm run dev       # live preview at http://localhost:5173/OpenPixel/
npm run build     # static site in .vitepress/dist
```

## Screenshots

Images live in `public/`: full screens in `screens/<lang>/` and feature crops in `crops/<lang>/`. They come from the iPad Pro 11" simulator (2420×1668, landscape) with the demo projects (`swift scripts/make-demo.swift <folder>` writes *Slime*, *Coin*, *Heart* and *Tree*; copy them into the app's `Documents/Sprites`), the light appearance and the Ember accent:

1. Take the screenshots into `raw/<lang>/<name>.png` (not committed), with the app set to that language in Preferences.
2. Run `swift scripts/crop.swift` to cut the feature crops (boxes in the script) and save everything as JPEG.

Each page in `guide/` has a twin with the same name in `es/guide/`; keep them in step.
