# Capas

Las capas están a la izquierda del timeline, la de arriba delante. Toca una capa para activarla; su fila se tiñe con el color de acento.

![El timeline con sus capas](/crops/es/timeline.jpg)

Cada fila tiene un **ojo** (mostrar u ocultar, ⇧X), un **candado** y los **puntos de continuidad** (ver [cels enlazados](./timeline#cels-enlazados)). Los mismos tres iconos de la cabecera actúan sobre todas las capas a la vez. Encima de la lista:

- **⚙** elige si el primer frame es el 0 o el 1;
- **+** añade una capa encima de la activa (⇧N); mantenlo pulsado para más opciones (abajo);
- la **papelera** elimina la capa activa;
- **↑ ↓** la suben o la bajan. También puedes arrastrar una capa para reordenarla.

## El menú de la capa

Mantén pulsado el nombre de una capa:

<div class="crop-row">

![El menú de la capa](/crops/es/layer-menu.jpg)

</div>

| Opción | Qué hace |
|---|---|
| **Renombrar** | También con un doble toque en el nombre. |
| **Bloquear** | En una capa bloqueada no se puede pintar ni mover. |
| **Continua** | Los frames nuevos enlazan el cel de esta capa en vez de copiarlo. |
| **Modo de fusión** | Normal, multiplicar, trama, superponer, oscurecer, aclarar, sobreexponer y subexponer color, luz fuerte y suave, diferencia, exclusión, suma, resta y división. |
| **Opacidad** | La opacidad de toda la capa. |
| **Convertir en tilemap** | Ver [Tilemaps](./tilemaps). |
| **Convertir en fondo** | Ver abajo. |
| **Agrupar** | Mete la capa en un grupo nuevo. |
| **Duplicar capa** | Una copia con todos sus cels. |
| **Fusionar hacia abajo** | La une con la capa de debajo, manteniendo el aspecto (modo de fusión y opacidad). |
| **Aplanar** | Junta todas las capas visibles en una. |
| **Seleccionar capas** | Empieza una selección del timeline con esta capa. |
| **Subir / bajar**, **meter en un grupo / sacar** | La reordena. |

## La capa de fondo

Como en Aseprite, una capa de fondo es opaca, aparece subrayada en la lista y siempre está abajo. Borrar o limpiar en ella deja el **color secundario** en vez de transparencia. Convierte una capa en fondo, y al revés, desde su menú.

## Grupos

Agrupa una capa desde su menú, varias desde una selección del timeline, o crea uno vacío desde el menú **+**. Los grupos se pliegan con su flecha. Su visibilidad, su bloqueo y su opacidad se aplican a todo lo que contienen, y al mover, duplicar o eliminar un grupo van con él sus capas. Una capa nueva añadida con un grupo activo va dentro de él.

## Capas nuevas desde el menú +

Mantén pulsado el **+** de encima de las capas:

<div class="crop-row">

![El menú +](/crops/es/new-layer-menu.jpg)

</div>

- **Nueva capa** y **Nuevo grupo**.
- **Nueva capa de tilemap**: ver [Tilemaps](./tilemaps).
- **Importar imagen o GIF…**: ver abajo.
- **Nueva capa de referencia** desde Archivos o Fotos: ver abajo.

En el menú Editar, **Nueva capa con la selección** (⌘J) copia los píxeles seleccionados a una capa nueva, y **Cortar a una capa nueva** (⇧⌘J) los mueve.

### Importar una imagen o un GIF

**Importar imagen o GIF…** trae un archivo de la app Archivos como una capa nueva de píxeles, encima de la activa y con el nombre del archivo:

- cada frame del GIF va a un frame del timeline, empezando por el **frame activo**;
- si el GIF tiene más frames que el sprite, se añaden los que faltan con las duraciones del GIF (los frames que ya existían conservan la suya);
- una imagen de otro tamaño se centra y se recorta;
- un PNG o un JPEG ocupa solo el frame activo;
- todo se deshace en un solo paso.

### Capas de referencia

Una capa de referencia guarda una foto o una imagen para calcar, como en Aseprite. La imagen conserva su resolución (no se convierte en píxeles; las fotos se guardan hasta 2048 px), empieza al 50 % de opacidad debajo del dibujo, no se puede pintar en ella y no se exporta. Muévela con la herramienta Mover; ajústala, rellena con ella, amplíala o redúcela desde su menú.
