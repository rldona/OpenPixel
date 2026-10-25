# Exportar

Toca **Exportar** (⇧⌘E), arriba a la derecha. Elige un formato y sus opciones, mira la vista previa y toca **Compartir o guardar…** para enviar el archivo con la hoja de compartir de iOS (Archivos, AirDrop, Mail…).

![Exportar un GIF](/crops/es/export.jpg)

## Formatos

| Formato | Qué obtienes |
|---|---|
| **PNG** | El frame actual. |
| **Secuencia PNG** | Un archivo por frame. |
| **GIF animado** | La animación, con la duración de cada frame. |
| **Hoja de sprites** | Todos los frames en fila, en un PNG, con datos JSON si quieres. |
| **Aseprite** | Un archivo `.aseprite` con capas, frames, tags y slices, para seguir trabajando en un ordenador. |
| **Slices** | Un PNG por slice (cuando el sprite tiene slices). |

## Opciones

- **Frames**: todos, el frame actual, un tag o un rango.
- **Capas**: las capas visibles o una capa.
- **Dirección** (GIF y secuencia PNG): como dice el tag, o adelante, atrás o ping-pong, con las repeticiones del tag.
- **Escala**: del 100 % al 1000 %, sin suavizado, para que los píxeles sigan nítidos. Los sprites con pixel ratio salen con él, como en el lienzo.
- **Exportar para Twitter**: en un GIF, ajusta la duración del último frame para que Twitter reproduzca bien la animación; en un PNG, mantiene las imágenes opacas como PNG en vez de JPEG.

## Hojas de sprites para motores de juego

![Opciones de la hoja de sprites](/crops/es/export-sheet.jpg)

Activa **Incluir datos JSON** para exportar, junto al PNG, un archivo JSON en el formato de Aseprite: la posición y la duración de cada frame, los tags con su dirección y los slices. La mayoría de los motores y sus importadores de Aseprite lo leen tal cual.
