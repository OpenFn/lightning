---
paths:
  - "assets/js/**/*.ts"
  - "assets/js/**/*.tsx"
  - "assets/css/**/*.css"
  - "lib/**/*.ex"
  - "lib/**/*.heex"
---

# Colours

Tailwind only generates a class it can find written out in full in the source.
A class it can't find produces no CSS, and nothing warns you. The element just
takes the colour of the text around it.

## Use real class names

Only use colours that exist in Tailwind or in the `@theme` block of
`assets/css/app.css`. `grey-*`, `text-black-800` and `text-white-400` look
right but generate nothing. `black` and `white` have no shades.

## Write every class out in full

Don't build class names from pieces, like `bg-#{@color}-50` or
`` `text-${color}-600` ``. Tailwind can't see them, so they only work by
accident when the same class is written somewhere else. Map each variant to its
full class names instead:

```elixir
defp alert_classes("danger"), do: "bg-red-50 text-red-800"
defp alert_classes("info"), do: "bg-blue-50 text-blue-800"
```

## Don't hand-type Tailwind colours

Don't copy a Tailwind colour as a literal value, like `#6b7280` for gray-500
or `rgb(79, 70, 229)` for indigo-600. We're on Tailwind v4, whose palette
differs from the v3 values most people remember, so a copied value sits
slightly off the colours around it.

- In `className`, use the class: `bg-gray-200`.
- Everywhere else (CSS files, inline `style`, SVG `fill` or `stroke`, chart
  props, colour constants in TS), use the CSS variable:
  `var(--color-gray-500)`.
- For opacity, use `color-mix(in oklab, var(--color-indigo-600) 20%, transparent)`,
  which is what Tailwind v4 does for `/20`.

Keep a literal value only where a library can't read a CSS variable, and say
why in a comment. Current cases:

- Monaco's `defineTheme`, and `.bg-vs-dark` in `app.css`, which matches
  Monaco's background.
- React Flow edge marker colours, which end up in an element id.
