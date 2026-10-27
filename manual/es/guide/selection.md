# Selección y transformación

## Seleccionar

El hueco de selección de la barra guarda cuatro herramientas, como en [Aseprite](https://www.aseprite.org/docs/selecting/):

| Herramienta | Tecla | Cómo selecciona |
|---|---|---|
| Marco rectangular | M | Arrastra un rectángulo. |
| Marco elíptico | ⇧M | Arrastra una elipse. |
| Lazo | Q | Dibuja alrededor de la zona. |
| Varita mágica | W | Toca un color: con tolerancia, contiguo o no, en la capa actual o en todas. |

La barra de opciones elige el modo: **reemplazar**, **añadir**, **restar** o **intersecar** (en lugar de Mayúsculas y Alt en un ordenador).

![Una selección con su barra de acciones](/crops/es/selection.jpg)

Mientras hay algo seleccionado, dibujar, rellenar y borrar se quedan dentro, y una barra te da las acciones habituales: transformar, duplicar y mover, cortar, copiar, pegar, eliminar, rellenar con el color principal, voltear, girar 90°, **organizar**, invertir y deseleccionar.

La barra ocupa el lugar de la cabecera del timeline, así que nunca tapa el dibujo. Al deseleccionar, aplicar o cancelar vuelve la cabecera. Con el timeline oculto (plegado o en modo enfoque), la barra flota abajo del lienzo.

Mientras arrastras un marco o el lazo, una etiqueta a su lado muestra el tamaño del área, contando solo la parte que queda dentro del sprite. Cuando ya hay una selección, la barra empieza con su tamaño y la posición de su esquina superior izquierda, como `12×8 · 3, 5`.

**Organizar** (el botón de capas) trae lo seleccionado al frente, un paso adelante, un paso atrás o lo envía al fondo. Cada parte de un dibujo vive en su propia capa, así que hay dos formas:

- **Solo este frame**: cambia solo el frame actual (o los frames elegidos en el timeline). El cel recibe un **z-index**, como en las propiedades del cel de Aseprite: se dibuja tantas capas más arriba o más abajo sin mover su capa. Un brazo puede estar detrás del cuerpo en el frame 1 y delante de todo en el frame 4.
- **En todos los frames**: la capa sube o baja en la pila.

También está en la barra de transformación, donde forma parte de la transformación: **Cancelar** devuelve el orden.

### Opacidad de la selección

Con una herramienta de selección (o Mover) y algo seleccionado, el deslizador de la barra izquierda fija la **opacidad de los píxeles seleccionados**: bájalo para atenuarlos y súbelo para recuperarlos. Parte de los píxeles tal como estaban, así que puedes probar valores sin miedo, y cada arrastre es un paso de deshacer. Cambia todas las capas que abarca la selección.

### Selección inteligente

- **Toca un elemento dibujado** con el marco o el lazo para seleccionar exactamente sus píxeles. Su capa pasa a ser la activa (la capa visible más alta bajo tu dedo). En modo añadir, sigue tocando para juntar varios elementos.
- Un marco o un lazo toma **todas las capas visibles** que tiene debajo (o las capas seleccionadas en el timeline) y, con **Ajustar al contenido**, se encoge a los píxeles dibujados que hay dentro. Sobre el lienzo vacío mantiene su forma.
- Mover, transformar, eliminar, rellenar y cortar esa selección cambia todas esas capas. Copiar las copia combinadas.
- **Todos los frames** aplica todo esto a todos los frames de la animación.

### Más comandos de selección

En el menú Editar (…): **seleccionar todo** (⌘A), **deseleccionar** (⌘D), **volver a seleccionar** (⇧⌘D), **invertir** (⇧⌘I), **seleccionar contenido de la capa** y, en **Modificar selección**, **expandir**, **contraer** o **borde** un número de píxeles.

## Mover y transformar

Con una herramienta de selección, **arrastra dentro de la selección** para mover sus píxeles; arrastra fuera para seleccionar otra vez. La herramienta Mover (V) mueve el cel entero, o la selección si la hay.

![Mover con la barra de transformación](/crops/es/stretch.jpg)

Mientras los píxeles flotan, el lienzo muestra asas:

- arrastra las **esquinas y los lados** para escalar (pasa del lado contrario para voltear);
- arrastra el **asa redonda** de arriba para girar alrededor del **pivote** (el punto del centro, que se puede arrastrar);
- la barra de transformación voltea, gira 90°, **organiza**, **borra** los píxeles flotantes (también ⌫), **mantiene la proporción**, **ajusta el ángulo** de 15 en 15° y elige giro **RotSprite** (pixel art más limpio) o **rápido**.

**Aplicar** (o tocar fuera, o ↩) suelta los píxeles; **Cancelar** (⎋) lo devuelve todo a su sitio. La transformación entera es un solo paso de deshacer. Con teclado, las flechas mueven los píxeles de 1 en 1 px.

### Estirar al mover

Si seleccionas medio personaje y lo mueves, normalmente se separa del resto. Mantén **Ctrl** mientras arrastras, como en Aseprite, o activa **Estirar al mover** en la barra de transformación (el botón de las cuatro flechas), y el hueco se rellena con el borde de la parte movida, de modo que el personaje se alarga en vez de partirse. Si lo desactivas, la parte vuelve a separarse. Dura una transformación.

### Transformar varios cels

Cuando hay varios cels, capas o frames seleccionados en el [timeline](./timeline#seleccionar-un-rango), mover, escalar, girar o voltear los cambia todos. La insignia **+N cels** de la barra de transformación dice cuántos más cambian.

## Comandos del lienzo

En el menú Editar: **tamaño del lienzo** (el lienzo muestra sus bordes con asas: arrastra un lado o una esquina hacia fuera para que crezca por ahí, o hacia dentro para encogerlo; con **En celdas** los lados caen en las líneas de la cuadrícula, para añadir tiles enteros. La barra muestra el tamaño nuevo y **Aplicar** lo cambia en un solo paso de deshacer. Los dibujos, tilemaps, slices y ejes de simetría mantienen su sitio), **recortar a la selección**, **recortar espacio vacío**, **rotar** y **voltear** el lienzo entero, y el **pixel ratio** (para sprites con píxeles anchos o altos).
