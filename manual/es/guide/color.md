# Color y paletas

El color está en el panel lateral, como en Aseprite: la paleta arriba, el selector de color debajo y, bajo él, las acciones de color.

<div class="crop-row">

![La paleta y el selector de color](/crops/es/color-panel.jpg)

</div>

## Color principal y secundario

Siempre tienes dos colores. El **principal** pinta; el **secundario** es lo que deja la goma en una capa de fondo, el final de un degradado y el contorno del texto.

Los dos **chips** bajo el selector los muestran con su valor hexadecimal:

- El chip con el borde del color de acento es el que editan el cuadrado y las barras. Toca el otro chip para editarlo a él.
- Toca la muestra del chip activo para abrir el **editor de color** completo.
- Toca el valor hexadecimal para escribir uno; se aplica al pulsar intro.
- Una insignia **!** en una muestra indica que ese color no está en la paleta. Tócala para añadirlo.
- **⇄** entre los chips (o X) cambia un color por el otro. **Apretar** el Apple Pencil Pro hace lo mismo.

## Colores recientes

La fila de encima de la paleta guarda los últimos 8 colores con los que has pintado, el más reciente primero. Toca uno para volver a usarlo: va al color que está editando el cuadrado. Muy útil con colores que no están en la paleta.

## El selector de color

Oculto al principio, para que la paleta tenga más sitio. El primero de los cuatro botones bajo los chips de color, **Selector de color**, lo muestra u oculta de nuevo; el panel recuerda lo que elijas. Los otros tres son **Sombreado de color**, **Tono/Saturación** y **Reemplazar color**. El selector tiene:

- el **cuadrado** ajusta la saturación (de izquierda a derecha) y el brillo (de abajo arriba);
- la barra de **tono** elige el tono;
- la barra de **opacidad** ajusta la transparencia.

Arrastras y el lápiz ya pinta con el color nuevo. Al elegir un color de la paleta o con el cuentagotas, los controles saltan a él, así que es fácil sacar un tono un poco más claro u oscuro.

## El editor de color

Al tocar la muestra del chip activo se abre el editor completo: un espectro, deslizadores **RGB** y **HSB**, el valor hexadecimal, la opacidad, **sombras y luces** del color actual y **armonías** (complementario, análogos, tríada, complementario dividido, tétrada). La mitad izquierda de la muestra de arriba es el color con el que empezaste: tócala para volver a él.

## La paleta

Toca un color para que pase a ser el principal. Los colores principal y secundario están marcados en la paleta.

El **+** que hay tras el último color añade el color principal, así que puedes montar una paleta a mano: eliges un color en el cuadrado, tocas +, y así sucesivamente. Para empezar de cero, elige **Vacía** como paleta inicial de un sprite nuevo, o **Nueva paleta vacía** en el menú **…**.

- **Editar** activa la edición de la paleta: selecciona una serie de colores para editar uno, hacer un **degradado** entre los extremos, **invertir**, **ordenar** (por tono, saturación, brillo o luminancia), **duplicar**, **eliminar** o arrastrar para reordenar. Todo se puede deshacer.
- El menú **…** carga una paleta predefinida (DawnBringer 32, PICO-8, Sweetie 16, Endesga 32, DawnBringer 16, Game Boy, grises…), hace una paleta con los colores del sprite, importa una (`.gpl`, `.hex`, `.pal`, `.txt`, `.png`, `.gif`), la exporta (`.gpl`, `.hex`) o fija la paleta por defecto para los sprites nuevos. Ahí aparecen también las paletas de las [extensiones](./scripts) instaladas.
- **Tus paletas**: una paleta importada se queda en **Mis paletas**, dentro de **Cargar predefinida**, con el nombre que trae el archivo (o el del archivo). **Guardar paleta como…** guarda ahí la paleta actual con el nombre que elijas; si vuelves a guardar con el mismo nombre, se sustituye. **Eliminar paleta guardada** quita una. Están disponibles en todos los sprites.
- Las paletas grandes se desplazan dentro del panel: Resurrect 64, por ejemplo, muestra unas pocas filas a la vez.

## Acciones de color

Los iconos de abajo, más el contorno:

| Botón | Qué hace |
|---|---|
| **Reemplazar color…** (⇧R) | Sustituye un color por otro, con una tolerancia, en el cel actual o en todos, y solo dentro de la selección si la hay. |
| **Tono/Saturación** | Una ventana flotante para cambiar el tono, la saturación, la luminosidad (o el valor) y el alfa, o los canales R, G, B y A, en el cel actual o en todos, con vista previa. **Aplicar** lo deja, **Cancelar** lo deshace. Mientras está abierta se puede mover y ampliar el lienzo, pero no pintar. |
| **Contorno…** (el botón ◉ de la barra de herramientas, o el menú ⋯) | Dibuja una línea de 1 px en el color principal o el secundario alrededor de lo dibujado (**Exterior**) o sobre su propio borde (**Interior**). La forma decide qué vecinos cuentan: **círculo** para esquinas redondeadas, **cuadrado** para esquinas en ángulo, **horizontal** o **vertical**, o elígelos uno a uno en la cuadrícula de 3×3. **Fondo** elige qué cuenta como vacío y **Mosaico** da la vuelta por los bordes. Se aplica a la selección si la hay, al cel actual o a los cels elegidos en el timeline, o a todos, con vista previa. |
| **Sombreado de color** | Una ventana flotante con una rampa de sombras del color principal; **Luminosidad, saturación y tono** muestra tres rampas más. Toca un tono para pintar con él; mantenlo pulsado para usarlo como secundario o añadirlo a la paleta. |

Solo hay una de las dos ventanas abierta a la vez: al abrir una se cierra la otra.
