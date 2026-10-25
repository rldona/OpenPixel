# Primeros pasos

OpenPixel es un editor de pixel art y animación para iPad, de código abierto y pensado para el Apple Pencil. Une la interfaz limpia de [Pixaki](https://pixaki.com/) con la forma de trabajar de [Aseprite](https://www.aseprite.org/docs/): un sprite tiene **capas** y **frames**, y la imagen donde se cruzan una capa y un frame es un **cel**.

![El editor de OpenPixel](/screens/es/editor.jpg)

## Qué ves

| Zona | Qué hace |
|---|---|
| **Barra superior** | Volver a la galería, las opciones de la herramienta activa en el centro, el **zoom** (400 % ⌄) y, a la derecha, el menú Editar (…), el modo enfoque, la cuadrícula, el modo mosaico y **Exportar**. |
| **Barra de herramientas** (izquierda) | Herramientas de dibujo, selección, mover, simetría, scripts y, abajo, deshacer y rehacer. Ver [Herramientas de dibujo](./drawing). |
| **Lienzo** (centro) | Donde dibujas. Pellizca para hacer zoom y arrastra con dos dedos para moverte. |
| **Panel lateral** (derecha) | La vista previa animada, la paleta (o el tileset de un tilemap), el selector de color, los colores recientes y las acciones de color. Ver [Color y paletas](./color). |
| **Timeline** (abajo) | Reproducción, frames, tags y capas. Ver [Capas](./layers) y [Frames y animación](./timeline). |

## Tu primer sprite en cinco pasos

1. En la galería, toca **Nuevo sprite**, elige un tamaño (de 16 a 256, o personalizado hasta 1024 px), un fondo y una paleta inicial, y toca **Crear**. Ver [Galería y proyectos](./gallery).
2. Dibuja con el Apple Pencil. Mantén pulsado el lienzo con un dedo para tomar un color, o toca uno en la paleta.
3. Toca **+ Frame** en el timeline para copiar el frame y dibujar la siguiente pose. Activa **Onion skin** para ver los frames de alrededor.
4. Toca **▶** para reproducir, o mira la vista previa del panel lateral mientras dibujas.
5. Toca **Exportar** y elige PNG, GIF, hoja de sprites o Aseprite. Ver [Exportar](./export).

::: tip Todo se guarda solo
Los sprites se guardan automáticamente, en segundo plano, en `Documents/Sprites` (visible en la app Archivos) como archivos `.openpixel` legibles.
:::

## Vocabulario básico

- **Sprite**: un dibujo o una animación, con su tamaño y su paleta.
- **Capa**: una hoja apilada sobre las demás, como el contorno encima de sus colores.
- **Frame**: un paso de la animación, con su propia duración en milisegundos.
- **Cel**: lo que muestra una capa en un frame.
- **Tag**: un rango de frames con nombre (Idle, Run…) que se reproduce por separado.
