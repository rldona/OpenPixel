# Galería y proyectos

La galería es la primera pantalla: todos tus sprites, con una miniatura. Los animados se reproducen en bucle (salvo con Reducir movimiento activado), y la etiqueta **▶ N** indica cuántos frames tienen.

![La galería](/screens/es/gallery.jpg)

## Encontrar un sprite

- **Buscar** (la lupa) filtra por nombre.
- **Todos / Animaciones / Estáticos** muestra todos los sprites, solo los animados o solo las imágenes sueltas.
- Mantén pulsado un sprite para **renombrarlo**, **duplicarlo** o **eliminarlo**.

## Un sprite nuevo

Toca **Nuevo sprite** (arriba a la derecha) o la tarjeta discontinua.

<div class="crop-row">

![Nuevo sprite](/crops/es/new-sprite.jpg)

</div>

- **Tamaño**: 16, 32, 64, 128 o 256 px, o el ancho y el alto que quieras hasta 1024 px.
- **Fondo**: transparente, blanco o negro.
- **Paleta inicial**: DawnBringer 32, PICO-8, Sweetie 16, Endesga 32 y más. Se puede cambiar después.

La vista previa de la derecha muestra lo que vas a obtener. Toca **Crear** para abrir el editor.

## Importar

**Importar** trae un archivo desde la app Archivos:

| Archivo | Qué obtienes |
|---|---|
| `.aseprite` / `.ase` | El sprite entero: capas, frames, tags y paleta. |
| GIF o PNG animado | Una capa con un frame por cada frame de la imagen, con la duración de cada uno. |
| PNG, JPEG | Un sprite de un frame (hasta 512 × 512 px). |

Para meter una imagen o un GIF en un sprite que ya está abierto, usa el menú de capas del timeline: ver [Capas](./layers#importar-una-imagen-o-un-gif).

## Dónde se guardan

Los sprites se guardan solos, en segundo plano, en **En mi iPad › OpenPixel › Sprites** como archivos `.openpixel` (JSON que se puede leer sin la app).
