# OpenPixel

Editor de pixel art y animación **open source** para iPad, pensado para Apple Pencil.

Toma la interfaz limpia de [Pixaki](https://pixaki.com/) y el modelo de trabajo de [Aseprite](https://www.aseprite.org/docs/): un sprite tiene **capas** y **frames**, y la imagen en cada cruce capa × frame es una **cel**.

> Estado: primera versión (0.1). Cubre los [Basics de Aseprite](https://www.aseprite.org/docs/basics/).

## Qué hace ya

- **Galería** de sprites con miniaturas, renombrar, duplicar, eliminar e importar PNG/GIF/JPEG.
- **Nuevo sprite**: tamaños rápidos (16–256) o personalizado hasta 1024 px, fondo transparente, blanco o negro, y paleta inicial (PICO-8, Sweetie 16, DawnBringer 16, grises).
- **Editor**
  - Lápiz, goma, cubo de pintura y cuentagotas, más simetría horizontal.
  - Cuadrícula de píxeles, zoom por niveles enteros y ajustar a pantalla.
  - Deshacer y rehacer (hasta 100 pasos).
- **Timeline** al estilo Aseprite
  - Capas: mostrar u ocultar, bloquear, renombrar, opacidad, reordenar y eliminar.
  - Frames: duplicar o crear vacío, mover, eliminar y fijar la duración en ms de cada uno.
  - Onion skin con el frame anterior y el siguiente.
  - Reproducción de la animación.
- **Color**: color principal y secundario, selector de color del sistema y paleta editable.
- **Exportar**: PNG del frame actual, hoja de sprites o GIF animado, a escala 1×–10× sin suavizado. Se comparte con la hoja de compartir de iOS.
- **Autoguardado** en `Documentos/Sprites` (visible desde la app Archivos), en un JSON `.openpixel` legible.

## Gestos

| Gesto | Acción |
|---|---|
| Apple Pencil | Dibuja con la herramienta activa |
| Un dedo | Dibuja, hasta que se usa el Pencil. Desde entonces, los dedos solo navegan |
| Pellizcar / dos dedos | Zoom y desplazamiento |
| Toque con dos dedos | Deshacer |
| Toque con tres dedos | Rehacer |
| Mantener un dedo (con Pencil) | Cuentagotas rápido |
| Doble toque en el Pencil | Alterna la goma y la herramienta anterior |

Con teclado se usan los atajos de Aseprite:

| Tecla | Acción |
|---|---|
| `B` | Lápiz |
| `E` | Goma |
| `G` | Cubo |
| `I` | Cuentagotas |
| `X` | Intercambiar colores |
| `⌥N` | Nuevo frame |
| `⇧N` | Nueva capa |
| `↩` | Reproducir |
| `←` `→` | Frame anterior / siguiente |
| `⌘Z` / `⇧⌘Z` | Deshacer / rehacer |

## Compilar

Requisitos: Xcode 16 o superior, [XcodeGen](https://github.com/yonaskolb/XcodeGen) e iPadOS 17 o superior.

```bash
brew install xcodegen
cp Config/Local.xcconfig.example Config/Local.xcconfig   # pon tu DEVELOPMENT_TEAM
xcodegen generate
open OpenPixel.xcodeproj
```

El `.xcodeproj` se genera a partir de `project.yml` y no se versiona.

Tests:

```bash
xcodebuild test -project OpenPixel.xcodeproj -scheme OpenPixel -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'
```

## Estructura

```
OpenPixel/
  App/         Punto de entrada y tema visual
  Model/       Sprite, capas, frames, cels, colores, paletas, rasterizado
  Document/    SpriteDocument (estado de edición + deshacer) y almacenamiento
  Rendering/   Conversión a CGImage y exportación PNG/GIF
  Views/       Galería, nuevo sprite, editor (lienzo UIKit, timeline, panel) y exportar
OpenPixelTests/
```

## Próximos pasos

- Tags de frames con dirección de bucle (adelante, atrás, ping-pong)
- Onion skin configurable, cels enlazadas y selección de rangos en el timeline
- Línea, rectángulo, elipse, selección y mover
- Modos de color indexado y escala de grises
- Abrir y guardar `.aseprite`

## Licencia

[MIT](LICENSE)
