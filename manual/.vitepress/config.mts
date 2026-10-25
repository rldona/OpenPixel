import { defineConfig } from 'vitepress'

// OpenPixel user manual. English at the root, Spanish under /es/ with the same page names,
// so the language switch lands on the same page. Published to GitHub Pages under /OpenPixel/.
const pages = [
  ['getting-started', 'Getting started', 'Primeros pasos'],
  ['gallery', 'Gallery and projects', 'Galería y proyectos'],
  ['drawing', 'Drawing tools', 'Herramientas de dibujo'],
  ['color', 'Color and palettes', 'Color y paletas'],
  ['selection', 'Selection and transform', 'Selección y transformación'],
  ['layers', 'Layers', 'Capas'],
  ['timeline', 'Frames and animation', 'Frames y animación'],
  ['tilemaps', 'Tilemaps', 'Tilemaps'],
  ['text-and-slices', 'Text and slices', 'Texto y slices'],
  ['export', 'Export', 'Exportar'],
  ['scripts', 'Scripts and extensions', 'Scripts y extensiones'],
  ['pencil', 'Apple Pencil and gestures', 'Apple Pencil y gestos'],
  ['shortcuts', 'Keyboard shortcuts', 'Atajos de teclado'],
  ['preferences', 'Preferences', 'Preferencias'],
] as const

const sidebar = (prefix: string, title: 'en' | 'es') => [
  {
    text: title === 'en' ? 'User guide' : 'Guía de uso',
    items: pages.map(([slug, en, es]) => ({ text: title === 'en' ? en : es, link: `${prefix}/guide/${slug}` })),
  },
]

export default defineConfig({
  base: '/OpenPixel/',
  title: 'OpenPixel',
  cleanUrls: true,
  lastUpdated: true,
  head: [['link', { rel: 'icon', href: '/OpenPixel/icon.png' }]],
  themeConfig: {
    logo: '/icon.png',
    socialLinks: [{ icon: 'github', link: 'https://github.com/rldona/OpenPixel' }],
    search: { provider: 'local' },
  },
  locales: {
    root: {
      label: 'English',
      lang: 'en',
      description: 'Open source pixel art and animation editor for iPad, built for Apple Pencil.',
      themeConfig: {
        nav: [{ text: 'Guide', link: '/guide/getting-started' }],
        sidebar: sidebar('', 'en'),
        outline: { label: 'On this page' },
      },
    },
    es: {
      label: 'Español',
      lang: 'es',
      link: '/es/',
      description: 'Editor de pixel art y animación de código abierto para iPad, pensado para el Apple Pencil.',
      themeConfig: {
        nav: [{ text: 'Guía', link: '/es/guide/getting-started' }],
        sidebar: sidebar('/es', 'es'),
        outline: { label: 'En esta página' },
        docFooter: { prev: 'Anterior', next: 'Siguiente' },
        lastUpdated: { text: 'Actualizado' },
        darkModeSwitchLabel: 'Apariencia',
        sidebarMenuLabel: 'Menú',
        returnToTopLabel: 'Volver arriba',
        langMenuLabel: 'Idioma',
      },
    },
  },
})
