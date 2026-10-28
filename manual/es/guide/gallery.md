# Galería y proyectos

La galería es la primera pantalla: todos tus sprites, con una miniatura. Los animados se reproducen en bucle (salvo con Reducir movimiento activado), y la etiqueta **▶ N** indica cuántos frames tienen.

![La galería](/screens/es/gallery.jpg)

## Encontrar un sprite

- **Buscar** (la lupa) filtra por nombre.
- **Todos / Animaciones / Estáticos** muestra todos los sprites, solo los animados o solo las imágenes sueltas.
- Mantén pulsado un sprite para **renombrarlo**, **duplicarlo**, **exportarlo** o **eliminarlo**. **Exportar** abre la misma ventana de [exportación](./export) que el editor, sin abrir el sprite.

## Carpetas

Agrupa proyectos en carpetas, y carpetas dentro de carpetas:

- Toca el botón de **carpeta** de arriba para crear una vacía donde estás, o mantén pulsado un proyecto y elige **Mover a carpeta › Nueva carpeta…**.
- Mete un proyecto o una carpeta en otra carpeta arrastrándolo sobre ella o con **Mover a carpeta** (las carpetas anidadas muestran su ruta, como *Personajes › Dummy*). Para subir algo un nivel, arrástralo sobre el botón de volver de arriba a la izquierda (**‹ Proyectos** o el nombre de la carpeta de arriba) o elige **Sacar de la carpeta**. Una carpeta no puede ir dentro de sí misma.
- Toca una carpeta para abrirla. Su tarjeta muestra cuatro proyectos de dentro (también de sus carpetas) y cuántos proyectos y carpetas contiene. Los sprites nuevos y las importaciones que hagas dentro van a ella, y los duplicados se quedan junto al original.
- **Todo se puede ordenar**, en la pantalla de inicio y en cada carpeta, con proyectos y carpetas mezclados. Arrastra una tarjeta sobre el lado izquierdo o derecho de otra para ponerla delante o detrás (una barra entre las tarjetas marca dónde), o sobre el centro de una carpeta para meterla dentro (la carpeta se ilumina). El orden se queda como lo dejes; los proyectos y carpetas nuevos, y los recién movidos, aparecen primero. Hasta que ordenes un sitio, muestra primero las carpetas y luego los proyectos más recientes.
- Mantén pulsada una carpeta para **renombrarla**, **moverla** o **eliminarla**. Eliminar una carpeta conserva lo que tiene: sus proyectos y carpetas suben un nivel.
- La búsqueda mira en todas las carpetas.

## Un sprite nuevo

Toca **Nuevo sprite** (arriba a la derecha) o la tarjeta discontinua.

<div class="crop-row">

![Nuevo sprite](/crops/es/new-sprite.jpg)

</div>

- **Tamaño**: 16, 32, 64, 128 o 256 px, o el ancho y el alto que quieras hasta 1024 px.
- **Fondo**: transparente, blanco o negro.
- **Paleta inicial**: DawnBringer 32, PICO-8, Sweetie 16, Endesga 32 y más, o **Vacía** para crear la tuya. Se puede cambiar después.

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
