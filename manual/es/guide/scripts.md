# Scripts y extensiones

OpenPixel ejecuta [scripts Lua de Aseprite](https://www.aseprite.org/docs/scripting/) y [extensiones](https://www.aseprite.org/docs/extensions/), así que buena parte de lo que ha hecho la comunidad de Aseprite funciona también en el iPad.

## Ejecutar un script

Toca **{ }** en la barra de herramientas (o Editar › Scripts):

<div class="crop-row">

![El menú de scripts](/crops/es/scripts-menu.jpg)

![El diálogo de un script](/crops/es/script-dialog.jpg)

</div>

- **Añadir script…** trae un archivo `.lua` de la app Archivos. Se queda en la lista.
- Toca un script para ejecutarlo. Los comandos que añaden las extensiones aparecen bajo el nombre de la extensión.
- Si el script muestra un diálogo, se abre como una ventana flotante que puedes arrastrar; su primer botón es la acción principal.
- Cada ejecución es **un solo paso de deshacer**.

Los scripts ven una parte de la API de Aseprite (Lua 5.4): `app`, `Sprite`, `Layer`, `Cel`, `Frame`, `Image`, `Color`, `Palette`, `Selection`, `Point`, `Size`, `Rectangle`, `Dialog`, eventos y temporizadores. Scripts de píxeles como [Isometric Box](https://darkwark.itch.io/isobox-for-aseprite) funcionan tal cual. Un script que necesita una parte de la API que OpenPixel no tiene se detiene y dice cuál.

::: info Seguros por diseño
Los scripts no pueden leer ni escribir archivos (salvo otros scripts de su propia carpeta) ni acceder a la red, y un script que tarda más de 10 segundos se detiene.
:::

## Extensiones

Un paquete `.aseprite-extension` puede añadir:

- **paletas**, en el menú **…** de la paleta;
- **matrices de tramado**, para el degradado;
- **scripts** y los comandos que añaden (`plugin:newCommand`), en el menú de scripts.

Instálalas en **Preferencias › Extensiones**, o abre el archivo desde la app Archivos. Los plugins pueden escuchar eventos y usar temporizadores, selecciones y sus propias preferencias, así que extensiones como [Magic Pencil](https://github.com/thkwznk/aseprite-scripts/tree/master/Magic%20Pencil) funcionan: lo que cambian después de un trazo se une al paso de deshacer de ese trazo. Los temas, idiomas y mapas de teclas son cosa de Aseprite y se quedan fuera.

Gestiona tus scripts en **Preferencias › Scripts**.
