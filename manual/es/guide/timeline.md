# Frames y animación

El timeline de abajo contiene los frames (numerados arriba), los tags encima de ellos y un cel por cada capa y frame.

![El timeline](/crops/es/timeline.jpg)

## El tamaño del timeline

Arrastra la **barra** de su borde superior para hacerlo más alto o más bajo; con un doble toque se ajusta a todas las capas. Si sigues empujando hacia abajo, se esconde tras una pequeña cápsula con reproducir, el número de frame y una barra para recorrer la animación. Toca su flecha o arrástrala hacia arriba para recuperar el timeline.

Después del último frame y de la última capa, unos frames y capas **proyectados**, tenues, continúan la cuadrícula. Toca uno para crear todo lo necesario hasta él en un solo paso.

## Frames

- **+ Frame** (⌥N) duplica el frame actual; mantenlo pulsado para uno vacío (⌥⇧N).
- La **papelera** elimina el frame actual.
- **Desliza sobre los números** de frame para recorrer la animación. Mantén pulsado un número y arrastra para mover ese frame; su menú tiene el resto.
- La columna del frame activo lleva un tinte, como la fila de la capa activa: se cruzan en el cel activo.
- La **duración** (100 ms ⌄) fija cuánto dura el frame actual: −/+, valores predefinidos hasta 4 s, o escribe cualquier valor hasta 65 535 ms. Los frames que duran más o menos que la mayoría muestran su duración bajo el número.
- `,` y `.` (o ← y →) van al frame anterior y al siguiente; Inicio y Fin, al primero y al último.

## Reproducción

**▶** (↩) reproduce el tag del frame actual, o todos los frames si no tiene. Los botones de al lado van al frame anterior y al siguiente; mantenlos pulsados para ir al primero y al último. Junto a ellos, **7 / 10** dice en qué frame estás. **1× ⌄** fija la velocidad, de 0,25× a 3×. La **vista previa** del panel lateral tiene su propio botón de reproducir, así que la animación sigue en marcha mientras dibujas.

## Tags

Un **tag** es un rango de frames con nombre y color, como *Idle* o *Jump*. Toca **Tag** (⌥⌘T) para crear uno sobre el frame actual o los frames seleccionados. Cada tag tiene:

- una **dirección**: adelante, atrás, ping-pong o ping-pong inverso;
- un número de **repeticiones** (0 repite sin fin).

Toca un tag para editarlo. Los tags que se solapan van en **bandas** distintas; **enfoca una banda** para que la reproducción se quede dentro de sus tags.

## Onion skin

**Onion skin** (papel cebolla) muestra los frames de antes y de después del actual, atenuados, para seguir el movimiento. Tócalo para activarlo; mantenlo pulsado para sus ajustes:

![Onion skin activado](/crops/es/onion.jpg)

- **Frames anteriores** y **siguientes**: de 0 a 3 en cada sentido;
- **opacidad**;
- **teñir**: rojo antes, azul después;
- **solo dentro del tag**.

Mientras está activado, los frames que muestra se marcan bajo sus números: en rojo los anteriores y en azul los siguientes.

## Cels enlazados

Los **cels enlazados** comparten una sola imagen: al editar uno cambian todos. En el timeline se dibujan como una sola píldora alargada.

- Marca una capa como **continua** (sus ●● pasan a ▬) y los frames nuevos enlazan su cel en vez de copiarlo.
- Enlaza o desenlaza cels desde el menú de un cel o desde una selección.

El menú de un cel fija también su **opacidad** (compartida por los cels enlazados).

## Seleccionar un rango

Toca **Seleccionar** y luego cels, números de frame o nombres de capa para seleccionar un bloque. Con él puedes **enlazar**, **desenlazar**, **limpiar**, **duplicar**, **invertir** o **eliminar**, crear un **tag** sobre sus frames, fijar la **duración** de varios frames a la vez y hacer un **bucle** con esa sección.

- **Elegir cels uno a uno**: cada cel que tocas fuera del bloque lo amplía para incluirlo, aunque esté en otra capa. Toca un cel dentro del bloque para recortarlo.
- **Mover y copiar bloques** de cels, frames o capas arrastrándolos. Un interruptor junto a **Listo** elige entre mover y copiar. Los bloques que sueltas más allá del último frame añaden frames.
- **Copiar y pegar entre sprites**: copia un bloque y pega cels, frames o capas desde el menú de un cel, de un número de frame o de una capa en cualquier sprite.
- Las [transformaciones](./selection#transformar-varios-cels) cambian todos los cels seleccionados.
- **Listo** mantiene los cels seleccionados (con contorno), así que rellenar, borrar o transformar en el lienzo les llega a todos. Toca cualquier cel para quitarlos.
