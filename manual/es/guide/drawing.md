# Herramientas de dibujo

<img class="rail" src="/crops/es/tool-rail.jpg" alt="La barra de herramientas">

Las herramientas están en la barra de la izquierda. Un triangulito en la esquina de un botón indica que guarda más de una herramienta: **mantenlo pulsado** para elegir otra. La barra recuerda la última que usaste en cada hueco.

| Hueco | Herramientas |
|---|---|
| Lápiz | Lápiz, spray |
| Goma | Goma |
| Cubo | Cubo de pintura, degradado |
| Cuentagotas | Cuentagotas |
| Formas | Línea, curva, rectángulo, elipse, contorno, polígono, texto (ver [Texto y slices](./text-and-slices)) |
| Selección | Marco rectangular y elíptico, lazo, varita mágica |
| Mover | Mover, slice |

Debajo están la **simetría** y el menú de **scripts** ({ }). Después:

- dos **deslizadores**, **tamaño** del pincel y **opacidad**, como los de Procreate: arrástralos arriba o abajo y el valor aparece al lado. El de tamaño se atenúa con herramientas sin pincel o con un pincel propio;
- **deshacer** y **rehacer**, abajo del todo.

<div class="clear"></div>

## Opciones de la herramienta

Las opciones de la herramienta activa están en el centro de la barra superior. Si una herramienta tiene más opciones de las que caben, la barra se desplaza de lado. Cada número (tamaño del pincel, opacidad, tolerancia…) abre un panel con valores habituales, un deslizador, botones −/+ grandes y un campo para escribirlo.

## Lápiz y pincel

- **Tamaño** de 1 a 32 px y **forma**: cuadrada, redonda o de **línea** (en cualquier ángulo, de 15 en 15°). `[` y `]` cambian el tamaño.
- **Pixel-perfect** limpia las esquinas de los trazos de 1 px. Viene desactivado y la elección se recuerda.
- El **spray** (⇧S) esparce píxeles dentro de un círculo; ajusta su anchura y velocidad.

### Pincel propio

Selecciona parte del dibujo y elige **Nuevo pincel con la selección** (⌘B) en el menú Editar, o mantén pulsado el lápiz en la barra:

<div class="crop-row">

![El menú del lápiz](/crops/es/pencil-menu.jpg)

</div>

El pincel se hace con los píxeles seleccionados de la capa activa, y OpenPixel pasa al lápiz para pintar con él. Un toque lo estampa; si arrastras, deja un rastro. Se mantiene aunque cambies de frame o de capa, así que puedes estampar el mismo sombrero en todos los frames de un paseo.

- Su miniatura aparece junto a las formas cuadrada, redonda y de línea: tócala para volver a él.
- **Usar el color** pinta solo su silueta con el color principal, en vez de con sus propios colores.
- La goma también lo usa.

## Goma, cubo y degradado

- La **goma** deja transparente. En una capa de fondo pinta el color secundario.
- El **cubo de pintura** rellena los píxeles **contiguos** o todos los de ese color (**global**), con una **tolerancia**. **Diagonales** deja que el relleno pase por las esquinas, y **Todas las capas** busca la zona en todas las capas visibles aunque pinte solo en la activa. Con una cuadrícula, puede **pararse en sus líneas**.
- El **degradado** (⇧G) rellena la zona que rellenaría el cubo pasando del color principal al secundario. Arrastra a través de la zona para darle dirección. Lineal o radial, suave o con tramado Bayer de 2×2, 4×4 u 8×8, o con una matriz de tramado de una [extensión](./scripts).

## Formas

- **Línea** (L) y **curva** (⇧L): para la curva, arrastra la línea y luego arrastra dos veces para doblar cada extremo.
- **Rectángulo** (U) y **elipse** (⇧U), rellenos o solo el contorno, con vista previa mientras arrastras. Los rectángulos pueden tener las esquinas redondeadas.
- **Contorno** (D): dibuja un contorno y se rellena al levantar.
- **Polígono** (⇧D): toca cada esquina y luego la primera (o **Listo**) para cerrarlo.

Los puntos de control y las esquinas se marcan en el lienzo mientras construyes una forma.

Mientras arrastras una línea, un rectángulo, una elipse o un degradado, una etiqueta a su lado muestra su tamaño en píxeles, como `12 × 8`. La línea muestra además cuántos píxeles mide y su ángulo: `12 × 8 · 12 px · 34°`. La etiqueta se queda junto a la esquina donde empezaste, para que el dedo o el Pencil no la tapen. Puedes desactivarla en [Preferencias](./preferences).

## Tintas y opacidad

Como en [Aseprite](https://www.aseprite.org/docs/ink/), la **tinta** decide cómo se mezcla un trazo con lo que ya hay:

| Tinta | Qué hace |
|---|---|
| Simple | Pinta el color. |
| Mezcla alfa | Mezcla los colores semitransparentes con lo que hay debajo. |
| Copiar alfa + color | Sustituye el píxel, transparencia incluida. |
| Bloquear alfa | Solo pinta sobre píxeles ya dibujados. |
| Sombreado | Cada pasada lleva los píxeles dibujados al color siguiente o anterior de la paleta. |

La **opacidad** de la herramienta se aplica una vez por trazo, así que pasar dos veces por el mismo sitio no la acumula. La **presión** del Apple Pencil puede cambiar el tamaño del pincel, la opacidad o las dos cosas.

## Cuentagotas

El cuentagotas (I) toma el color de toda la imagen o solo de la capa activa. No hace falta cambiar a él: **mantén pulsado** el lienzo con un dedo mientras dibujas con el Pencil, o con teclado mantén **⌥** y toca.

## Simetría

El botón de simetría de la barra refleja lo que dibujas, como en [Aseprite](https://www.aseprite.org/docs/symmetry/): en horizontal, en vertical o en las dos.

- Tócalo para activar o desactivar la simetría; mantenlo pulsado para elegir los ejes o centrarlos. Mientras está activa, su esquina dice qué ejes: **H**, **V** o **HV**.
- Arrastra un eje por su asa (debajo o a la derecha del sprite) para moverlo de medio en medio píxel, de modo que pueda pasar entre dos píxeles o por el centro de uno.

## Cuadrícula y modo mosaico

- **#** en la barra superior muestra la cuadrícula de píxeles. Mantenlo pulsado para definir una **cuadrícula** de cualquier tamaño de celda y desplazamiento, que se guarda con el sprite. **Ajustar a la cuadrícula** funciona como en Aseprite: el lápiz, la goma y el spray dibujan libremente dentro de las celdas (un pincel del tamaño de una celda rellena celdas enteras), las líneas, curvas y polígonos van de esquina a esquina, los rectángulos y elipses cubren celdas enteras, los marcos y los slices toman celdas enteras, y los movimientos van de celda en celda.
- El **modo mosaico** (en el menú de la cuadrícula: mantén pulsado **#**) muestra el sprite repetido a su alrededor, en horizontal, en vertical o en ambos. Los trazos, las formas y los rellenos cruzan los bordes, para hacer texturas sin costuras. Con el modo mosaico activo, **Tamaño del lienzo** rellena la zona nueva con la repetición, como en Aseprite: arrastra el borde derecho hacia fuera y el dibujo continúa por ahí. **Fijar la repetición** (en el mismo menú, con el modo mosaico activo) la convierte en parte del dibujo: el lienzo pasa a ser ×2, ×3 o ×4 copias de sí mismo en los ejes del mosaico, con todas las capas y frames repetidos (los tilemaps reutilizan sus tiles), en un solo paso de deshacer.
