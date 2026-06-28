# Storybook

A catalogue of Lightning's UI: the React components that ship in `assets/js/`,
plus React **clones** of the server-rendered (Phoenix LiveView / HEEx)
components, so every visual element of the app is represented in one place.

## Running it

From the `assets/` directory:

```bash
npm run storybook         # dev server on http://localhost:6006
npm run build-storybook   # static build into assets/storybook-static/
```

## Layout

```
js/storybook/
  Introduction.mdx        # in-Storybook landing page
  _shared/showcase.tsx    # small presentational helpers (Showcase/Section/Row/Specimen)
  foundations/            # Colors, Typography, Icons (design tokens)
  editor/                 # the collaborative workflow editor (Canvas, IDE, Diagram/*)
  pages/                  # LiveView page composites assembled from parts
  components/             # stories for real React components from assets/js/
  liveview/               # React clones of HEEx/LiveView components
```

Story titles map to the sidebar:

| Title prefix          | Contents                                                  |
| --------------------- | --------------------------------------------------------- |
| `Foundations/*`       | Design tokens (color scales, type, icons).                |
| `Editor/*`            | The collaborative workflow editor — the `Canvas` and full-screen `IDE` composites (built from the real `from-workflow` transform, node/edge renderers and inspector) plus `Diagram/*` node/edge pieces. |
| `Pages/*`             | LiveView page composites (App Shell, Dashboard, Project Settings, History) showing how the parts connect into a whole. |
| `Components/*`        | Real React components imported from `assets/js/`.         |
| `LiveView Clones/*`   | React re-creations of HEEx components (see below).        |

The left app sidebar (`#sidebar-panel`/`#side-menu`) and shared page frame live in
`liveview/_shell.tsx`; the clone deliberately reuses the real element ids and
classes so collapse/expand and the theme scopes are driven by `app.css` itself.

## The "LiveView Clone" convention

Much of Lightning's UI is rendered on the server with HEEx and never existed as
a React component. To represent those elements here without a running Phoenix
server, they are re-created as small **presentational** React components, with
the story titled using a `(LiveView Clone)` suffix — e.g.
_History Table (LiveView Clone)_.

Each clone (in `liveview/`):

- mirrors the markup and Tailwind classes of its Elixir source so it looks
  identical;
- is purely visual — no `phx-*` bindings, LiveView events or data loading;
- documents the Elixir source module/function it was cloned from at the top of
  the file.

> ⚠️ Clones are a visual reference, not the source of truth. If you change a
> HEEx component, update its clone here too. They are intentionally not wired
> into the running app.

## How the design system is wired

`.storybook/preview.ts` imports the real application stylesheet
(`assets/css/app.css`), and `.storybook/main.ts` runs Tailwind v4 through
`@tailwindcss/vite` using the app's own `tailwind.config.ts`. So tokens, custom
utilities, heroicon/lucide masks and fonts match production.

Two small accommodations are made because Storybook builds with Vite alone (no
Elixir toolchain):

- `main.ts` strips the `@import` of `petal_components` CSS (it lives under
  `deps/`) and pins an empty PostCSS config so the app's classic `.postcssrc`
  (which registers Tailwind as a v3-style PostCSS plugin) isn't applied.
- `tailwind.config.ts` resolves its own directory in a CJS/ESM-safe way so it
  loads under both the standalone Tailwind CLI and `@tailwindcss/vite`.

Because Tailwind v4 only emits utilities (and theme variables) that appear in
source, foundation stories that enumerate tokens (e.g. Colors, Icons) spell out
class names literally rather than building them dynamically.

## Adding a story

```tsx
import type { Meta, StoryObj } from '@storybook/react-vite';

import { MyComponent } from '#/path/to/MyComponent';

const meta = {
  title: 'Components/My Component',
  component: MyComponent,
} satisfies Meta<typeof MyComponent>;

export default meta;

type Story = StoryObj<typeof meta>;

export const Default: Story = { args: {} };
```

Stories are picked up from anywhere under `assets/js/` matching
`*.stories.@(ts|tsx|js|jsx)` (and `*.mdx`). They are type-checked by
`npm run check` and linted by `npm run lint`, so keep them clean under the
project's strict TypeScript and ESLint config (import order, jsx-a11y, etc.).
Components that need app stores, contexts, Y.Doc or Phoenix channels generally
can't render in isolation; prefer a small clone or a minimal provider decorator.
