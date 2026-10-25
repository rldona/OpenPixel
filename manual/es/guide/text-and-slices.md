# Texto y slices

## Texto

La **herramienta de texto** (T) escribe texto en píxeles:

1. Toca el lienzo donde va el texto y escribe.
2. Elige la fuente en la barra de opciones: dos fuentes de píxeles incluidas (5×7 con minúsculas y acentos, y mayúsculas de 3×5) a escalas de píxel entero, o una fuente del sistema dibujada sin suavizado.
3. Ajusta el **espaciado** entre letras y entre líneas, la **alineación** y, si quieres, un **contorno de 1 px** con el color secundario.

El texto queda como píxeles flotantes que puedes mover, escalar o girar, como cualquier [transformación](./selection#mover-y-transformar), antes de aplicarlo.

## Slices

Un **slice** es un rectángulo con nombre y color sobre una parte del sprite, como en [Aseprite](https://www.aseprite.org/docs/slices/), pensado para motores de juego: un botón con bordes que se estiran, una caja de colisión, un punto de pivote.

- La herramienta slice (⇧C) comparte hueco con Mover. Arrastra para dibujar un slice.
- Arrastra dentro de un slice para moverlo, o un lado o una esquina para cambiar su tamaño. Toca otro slice para elegirlo.
- Sus propiedades fijan el nombre, el color, un **centro 9-slice** (la parte que se estira) y un **pivote**.
- Si cambias un slice en un frame posterior, se añade una clave ahí, así que los slices pueden seguir la animación.

Los slices se exportan como un PNG cada uno, o se listan en el JSON de una hoja de sprites. Ver [Exportar](./export).
