# OpenPixel

Editor de pixel art y animación **open source** para iPad, pensado para Apple Pencil.

[English](README.md) · La documentación principal está en inglés; esta es una traducción.

Toma la interfaz limpia de [Pixaki](https://pixaki.com/) y el modelo de trabajo de [Aseprite](https://www.aseprite.org/docs/): un sprite tiene **capas** y **frames**, y la imagen en cada cruce capa × frame es una **cel**.

> Estado: primera versión (0.1). Cubre los [Basics de Aseprite](https://www.aseprite.org/docs/basics/).

## Qué hace ya

- **Proyectos**: galería con miniaturas, búsqueda, filtros (todos, animaciones, estáticos), renombrar, duplicar, eliminar e importar PNG/GIF/JPEG.
- **Nuevo sprite**: tamaños rápidos (16–256) o personalizado hasta 1024 px, fondo transparente, blanco o negro, y paleta inicial (PICO-8, Sweetie 16, DawnBringer 16, grises).
- **Editor**
  - Lápiz, **spray** (⇧S), goma, cubo de pintura, **degradado**, cuentagotas, línea, **curva**, rectángulo, elipse, **contorno** y **polígono** (como en [Aseprite](https://www.aseprite.org/docs/drawing/)).
    - Curva: arrastra la línea y luego arrastra dos veces para curvar cada extremo. Polígono: toca cada esquina y toca la primera (o Listo) para cerrarlo. Contorno: dibuja el borde y se rellena al levantar. Degradado (⇧G, junto al cubo): arrastra sobre la zona que rellenaría el cubo para pasar del color principal al secundario, lineal o radial, suave o con tramado Bayer de 2×2, 4×4 u 8×8. Los puntos de control y las esquinas se marcan en el lienzo.
  - Barra de opciones flotante según la herramienta:
    - pincel cuadrado, redondo o de **línea** (con cualquier ángulo, en pasos de 15°) de 1 a 8 px;
    - **pincel propio**: selecciona una parte del dibujo y elige Editar > Nuevo pincel con la selección (⌘B) para pintar con ella, con sus colores o con el color principal;
    - ancho y velocidad del spray;
    - pixel-perfect opcional para trazos de 1 px sin esquinas dobles (desactivado por defecto; se recuerda tu elección);
    - formas con o sin relleno, con vista previa mientras arrastras, y rectángulos con esquinas redondeadas;
    - cubo contiguo o global (sustituye el color en toda la cel), tolerancia, diagonales (se extiende también por las esquinas) y «Todas las capas» para delimitar la zona con todas las capas visibles pintando solo la activa;
    - cuentagotas: la imagen completa o solo la capa activa;
    - si una herramienta tiene más opciones de las que caben, la barra se desplaza en horizontal.
  - **Simetría** ([la de Aseprite](https://www.aseprite.org/docs/symmetry/)): horizontal, vertical o ambas. Toca el botón del raíl para activarla o desactivarla; mantenlo pulsado para elegir los ejes o centrarlos. Arrastra un eje por su tirador (debajo o a la derecha del sprite) para moverlo en pasos de medio píxel, de modo que puede pasar entre dos píxeles o por el centro de uno.
  - **Modo mosaico** (el Ver > Modo mosaico de Aseprite, el botón junto a la cuadrícula): el sprite se ve repetido alrededor, en horizontal, en vertical o en ambas direcciones, y los trazos, formas y rellenos pasan de un borde al contrario, para hacer texturas sin costuras.
  - **Apretar** el Apple Pencil Pro intercambia el color principal y el secundario (Aseprite pinta con el secundario con el clic derecho).
  - **Tintas** ([las de Aseprite](https://www.aseprite.org/docs/ink/)): simple, mezcla alfa, copiar alfa + color, bloquear alfa (pinta solo sobre lo dibujado) y sombreado (cada pasada mueve lo dibujado al color siguiente o anterior de la paleta). **Opacidad** de la herramienta, aplicada una vez por trazo para que repasar no acumule.
  - La **presión del Apple Pencil** puede cambiar el grosor y/o la opacidad.
  - Cuadrícula de píxeles, zoom por niveles enteros y ajustar a pantalla.
  - Deshacer y rehacer (hasta 100 pasos).
- **Timeline** al estilo Aseprite, compacto como el suyo: arrastra su borde superior para hacerlo más alto o más bajo (doble toque en el borde para ver todas las capas). Mantiene a la vista la capa con la que trabajas, y la fila de tags solo aparece cuando el sprite tiene tags.
  - Capas: mostrar u ocultar, bloquear, renombrar, opacidad, eliminar y reordenar arrastrando. Los iconos de ojo, candado y continuidad de la cabecera actúan sobre todas las capas.
  - **Capa de fondo** como en Aseprite: opaca, subrayada, siempre abajo, y al borrar o vaciar deja el color secundario. Se convierte en capa normal (y al revés) desde su menú.
  - Frames: «+ Frame» duplica el actual y, si lo mantienes pulsado, ofrece un frame vacío. También se pueden reordenar arrastrando su número, eliminar y fijar la duración de cada uno: con −/+, con valores rápidos de hasta 4 s o escribiendo cualquier valor hasta 65 535 ms. Los frames que duran distinto que la mayoría muestran su duración bajo el número.
  - **Tags**: rangos de frames con nombre y color, dirección (adelante, atrás, ping-pong, ping-pong inverso) y repeticiones.
  - **Reproducción**: reproduce el tag del frame actual (o todos los frames), a velocidad de 0,25× a 3×, con botones de primer, anterior, siguiente y último frame (Inicio y Fin en teclado).
  - **Onion skin** configurable: de 0 a 3 frames antes y después, opacidad, tinte rojo/azul y opción de limitarlo al tag.
- **Selección inteligente**: con el marco o el lazo, toca un elemento dibujado para seleccionar exactamente sus píxeles; su capa pasa a ser la activa (la capa visible más alta bajo el dedo). En modo añadir vas sumando elementos. Un marco o un lazo coge todas las capas visibles que abarca (o las capas elegidas en el timeline) y se ajusta a los píxeles dibujados que contiene (se puede desactivar con «Ajustar al contenido»); sobre lienzo vacío mantiene su forma. Mover, transformar, borrar, rellenar (cada capa recolorea sus propios píxeles) y cortar esa selección cambia todas esas capas; copiar las copia fusionadas. Activa «Todos los frames» para aplicarlo a todos los frames de la animación.
- **Mover sin cambiar de herramienta**: con una herramienta de selección, arrastra dentro de la selección para mover sus píxeles (con asas de escalar y rotar); arrastra fuera para seleccionar de nuevo. **Las transformaciones siguen la selección del timeline**: con varias cels, capas o frames seleccionados en el timeline, mover, escalar, rotar o voltear los cambia todos, como en Aseprite.
- **Herramienta de texto** (T): toca el lienzo y escribe. Dos fuentes de píxel incluidas (5×7 con minúsculas y tildes, y 3×5 de mayúsculas) a escala de píxeles enteros, o fuentes del sistema sin suavizado. Espacio entre letras y líneas, alineación y contorno de 1 px con el color secundario. El texto queda como píxeles flotantes que puedes mover, escalar o rotar antes de aplicarlo.
- **Color y paletas**, como en Aseprite:
  - Editor de color con espectro, deslizadores RGB y HSB, hex, opacidad, sombras y luces, y armonías (complementario, análogos, tríada…), con aviso y «añadir a la paleta» cuando el color no está en ella.
  - Color principal y secundario (marcados en la paleta), intercambiar y **Reemplazar color** (⇧R) con tolerancia, en la cel actual o en todas, dentro de la selección.
  - Edición de paleta: seleccionar un tramo de colores para editarlo, degradado, invertir, ordenar (tono, saturación, brillo, luminancia), duplicar, eliminar y reordenar arrastrando. Todo se puede deshacer.
  - Paletas predefinidas (DawnBringer 32, PICO-8, Sweetie 16, Endesga 32, DawnBringer 16, Game Boy, grises), paleta desde los colores del sprite, importar (.gpl, .hex, .pal, .txt, .png, .gif) y exportar (.gpl, .hex), y paleta por defecto para los sprites nuevos.
- **Exportar**: PNG del frame actual, hoja de sprites o GIF animado, a escala 1×–10× sin suavizado. La hoja de sprites y el GIF pueden limitarse a un tag; el GIF respeta su dirección y sus repeticiones. Se comparte con la hoja de compartir de iOS.
- **Autoguardado** en `Documentos/Sprites` (visible desde la app Archivos), en un JSON `.openpixel` legible, en segundo plano.
- **Selección y transformar** como en Aseprite: marco rectangular y elíptico, lazo y varita mágica; modos añadir, restar e intersecar; hormigas; cortar, copiar y pegar; mover, escalar, rotar con RotSprite y pivote, voltear, rotar 90° y recortar el lienzo.
- **Cels enlazadas y rangos**: capas continuas cuyas cels se enlazan al crear frames, desenlazar, y modo «Seleccionar» en el timeline (cels, números de frame o nombres de capa) para enlazar, vaciar, duplicar, invertir o eliminar bloques.
- **Timeline avanzado**: mover y copiar bloques de cels, frames o capas arrastrando, también más allá del último frame (un interruptor junto a «Listo» elige mover o copiar); copiar y pegar entre sprites; sección de bucle; tags y duración sobre los frames seleccionados; enfocar una banda de tags para reproducir solo sus tags; opacidad por cel; duplicar capa; doble toque para renombrar; primer frame numerado desde 0 o 1; y los atajos de Aseprite `,` `.` y ⇧X.
- **Preferencias**: inglés (por defecto) o español, y tema claro, oscuro o el del sistema.
- Edición a pantalla completa, sin barra de estado, y modo enfoque (toque con cuatro dedos o Tab) que deja solo el lienzo.
- **Rendimiento**: lienzo con capas de GPU y repintado parcial; los trazos van fluidos también en 256×256.

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
| Apretar el Apple Pencil Pro | Intercambia el color principal y el secundario |

Con teclado se usan los atajos de Aseprite:

| Tecla | Acción |
|---|---|
| `B` / `⇧S` | Lápiz / spray |
| `E` | Goma |
| `G` / `⇧G` | Cubo / degradado |
| `I` | Cuentagotas |
| `L` / `⇧L` | Línea / curva |
| `D` / `⇧D` | Contorno / polígono |
| `U` / `⇧U` | Rectángulo / elipse |
| `[` `]` | Tamaño del pincel |
| `⌘B` | Nuevo pincel con la selección |
| `↩` / `⎋` | Al construir una curva o un polígono: listo / cancelar |
| `X` | Intercambiar colores |
| `⌥N` | Nuevo frame (duplica el actual) |
| `⌥⇧N` | Nuevo frame vacío |
| `⇧N` | Nueva capa |
| `↩` | Reproducir |
| `⌥⌘T` | Nuevo tag |
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

- Modos de color indexado y escala de grises
- Abrir y guardar `.aseprite`

## Contribuir

El código, los comentarios, los commits, las issues y los pull requests se escriben en **inglés**. Los textos nuevos de la interfaz usan una clave en inglés y su traducción en `OpenPixel/Resources/es.lproj/Localizable.strings`.

## Licencia

[MIT](LICENSE)
