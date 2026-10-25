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

Mientras hay algo seleccionado, dibujar, rellenar y borrar se quedan dentro, y una barra flotante te da las acciones habituales: transformar, duplicar y mover, cortar, copiar, pegar, eliminar, rellenar con el color principal, voltear, girar 90°, invertir y deseleccionar.

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
- la barra de transformación voltea, gira 90°, **mantiene la proporción**, **ajusta el ángulo** de 15 en 15° y elige giro **RotSprite** (pixel art más limpio) o **rápido**.

**Aplicar** (o tocar fuera, o ↩) suelta los píxeles; **Cancelar** (⎋) lo devuelve todo a su sitio. La transformación entera es un solo paso de deshacer. Con teclado, las flechas mueven los píxeles de 1 en 1 px.

### Estirar al mover

Si seleccionas medio personaje y lo mueves, normalmente se separa del resto. Mantén **Ctrl** mientras arrastras, como en Aseprite, o activa **Estirar al mover** en la barra de transformación (el botón de las cuatro flechas), y el hueco se rellena con el borde de la parte movida, de modo que el personaje se alarga en vez de partirse. Si lo desactivas, la parte vuelve a separarse. Dura una transformación.

### Transformar varios cels

Cuando hay varios cels, capas o frames seleccionados en el [timeline](./timeline#seleccionar-un-rango), mover, escalar, girar o voltear los cambia todos. La insignia **+N cels** de la barra de transformación dice cuántos más cambian.

## Comandos del lienzo

En el menú Editar: **recortar a la selección**, **recortar espacio vacío**, **rotar** y **voltear** el lienzo entero, y el **pixel ratio** (para sprites con píxeles anchos o altos).
