# Tilemaps

Una **capa de tilemap** se dibuja con tiles, como en [Aseprite](https://www.aseprite.org/docs/tilemap/): una cuadrícula de celdas en la que cada una muestra un tile del **tileset** de la capa. Si cambias un tile, cambian todas las celdas que lo usan.

## Crear una

- En el menú **+** del timeline, **Nueva capa de tilemap**: sus tiles toman el tamaño de las celdas de la cuadrícula (defínela manteniendo pulsado **#**).
- O convierte una capa desde su menú con **Convertir en tilemap**. **Convertir en capa normal** la devuelve.

Mientras una capa de tilemap está activa, el panel lateral muestra las pestañas **Paleta | Tileset** en el sitio de la paleta, y se abre en **Tileset**.

## Píxeles o tiles

El selector de arriba del tileset elige qué dibujas.

### Píxeles

Pintas píxeles como siempre, y el modo del tileset decide qué pasa con los tiles:

| Modo | Qué hace una edición |
|---|---|
| **Manual** | Editar una celda edita su tile, así que cambian todas sus copias. |
| **Auto** | Cada celda editada recibe un tile igual, nuevo o reutilizado; los tiles que nadie usa desaparecen. |
| **Apilar** | Cada edición crea un tile nuevo. |

### Tiles

Elige un tile en el tileset y colócalo:

- el **lápiz** coloca el tile elegido;
- la **goma** vacía celdas;
- el **cubo** rellena celdas conectadas;
- el **cuentagotas** toma el tile que hay bajo tu dedo.

## Exportar el tileset

El botón de compartir junto al tileset lo exporta como una tira PNG.
