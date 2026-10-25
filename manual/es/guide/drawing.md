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

- los **colores**: el principal sobre el secundario. Toca para intercambiarlos; mantén pulsado para editar el principal;
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

- **#** en la barra superior muestra la cuadrícula de píxeles. Mantenlo pulsado para definir una **cuadrícula** de cualquier tamaño de celda y desplazamiento, que se guarda con el sprite. **Ajustar a la cuadrícula** hace que los marcos tomen celdas enteras y que los movimientos vayan de celda en celda.
- El **modo mosaico** (el botón junto a la cuadrícula) muestra el sprite repetido a su alrededor, en horizontal, en vertical o en ambos. Los trazos, las formas y los rellenos cruzan los bordes, para hacer texturas sin costuras.
