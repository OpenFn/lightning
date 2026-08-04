---
paths:
  - "assets/js/**/*.tsx"
  - "lib/**/*.heex"
---

# UI Patterns and Guidelines

This document captures UI/UX patterns and design conventions for the Lightning collaborative editor.

**Scope:** These patterns apply specifically to the collaborative editor (`assets/js/collaborative-editor/`).

**Tailwind version:** this repo runs **Tailwind v4**, via the Elixir `tailwind` package
(the exact pin is in `config/config.exs`, under `config :tailwind`) — *not* the npm
`tailwindcss` package. The `tailwindcss@3.3.5` entry in `assets/package-lock.json` is stale and
unused; do not audit Tailwind from it.

Two places hold configuration, and the split matters:
- **Design tokens** (`primary-*`, `secondary-*`, `danger-*`, fonts) are defined in the
  `@theme` block of `assets/css/app.css`. New colours go there — v4 does not read them from
  `theme.extend.colors`.
- **Plugins, custom variants, keyframes and the `hero-*`/`lucide-*` icon utilities** live in
  `assets/tailwind.config.ts`, loaded by the v4 `@config` directive at `assets/css/app.css:7`.
  Removing that directive removes every icon in the app.

v4-only utilities are in active use — `inset-ring-*`, `shadow-xs`, `focus-visible:outline-*`.
They are correct; do not rewrite them to v3 equivalents.

## Button Colors and Variants

### Color Standards

**Primary Buttons (Main Actions):**
- Normal: `bg-primary-600`
- Hover: `hover:bg-primary-500`
- Disabled: `disabled:bg-primary-300 disabled:hover:bg-primary-300`
- Text: `text-white`
- Shadow: `shadow-xs` (v4 spelling; v3 called this `shadow-sm`)
- Focus: `focus-visible:outline-primary-600`, with
  `focus-visible:outline-2 focus-visible:outline-offset-2` from the shared base

**Danger Buttons (Destructive Actions):**
- Normal: `bg-red-600`
- Hover: `hover:bg-red-500`
- Disabled: `disabled:bg-red-300 disabled:hover:bg-red-300`
- Text: `text-white`
- Shadow: `shadow-xs`
- Focus: `focus-visible:outline-red-600`

**Secondary Buttons (Alternative Actions):**
- Normal: `bg-white text-gray-900`
- Ring: `inset-ring inset-ring-gray-300`
- Hover: `hover:inset-ring-gray-400`
- Disabled: `disabled:bg-gray-50 disabled:text-gray-400`, plus the matching
  `disabled:hover:` overrides — see the disabled-state rule below
- Shadow: `shadow-xs`

**Ghost Buttons (Low-emphasis, in-panel actions):**
- Normal: `bg-transparent text-gray-700`
- Hover: `hover:bg-gray-100 hover:text-gray-900`
- Disabled: `disabled:bg-transparent disabled:text-gray-400 disabled:hover:bg-transparent
  disabled:hover:text-gray-400`
- Focus: `focus-visible:outline-gray-400`
- No shadow — the flat look is the point

**When to use each:**
- **Primary (bg-primary-600)**: Main call-to-action buttons (Save, Create, Run, etc.)
- **Danger (bg-red-600)**: Destructive actions (Delete, Remove, Reset, etc.)
- **Secondary (bg-white)**: Cancel, alternative actions, less emphasis

## Disabled Button States

Tailwind's `hover:` classes continue to apply even when `disabled` is true. For every `hover:` class, add a corresponding `disabled:hover:` class that matches the disabled state appearance.

### Pattern Examples

**Primary/Danger buttons:**
```tsx
className="
  bg-primary-600 hover:bg-primary-500 text-white shadow-xs
  focus-visible:outline-primary-600
  disabled:bg-primary-300 disabled:hover:bg-primary-300
  disabled:cursor-not-allowed
"
```

**Secondary buttons (with rings):**
```tsx
className="
  bg-white text-gray-900 shadow-xs inset-ring inset-ring-gray-300
  hover:inset-ring-gray-400
  disabled:bg-gray-50 disabled:text-gray-400
  disabled:hover:bg-gray-50 disabled:hover:inset-ring-gray-300
  disabled:cursor-not-allowed
"
```

**Note:** Secondary buttons need both `disabled:hover:bg-*` AND `disabled:hover:inset-ring-*` overrides.

## Reference Components

Use these as examples when creating new buttons:

1. **Button.tsx** - Shared component with correct patterns for all five variants (`primary`,
   `danger`, `secondary`, `ghost`, `nakedClose`)
2. **RunRetryButton.tsx** - Gold standard for complex split button states
3. **Header.tsx SaveButton** - Demonstrates standalone and split button patterns

**Pattern Usage:** Most buttons in the collaborative editor are inline `<button>` elements rather than using the shared `Button` component. When adding new buttons, check similar existing buttons for consistency and always include proper `disabled:hover:` overrides.

## Testing Disabled States

1. **Visual test:** Hover over disabled button - should see NO visual change
2. **Cursor test:** Should show "not-allowed" cursor when hovering
3. **Consistency test:** Same button variant should look identical when disabled across the app

## Related Issues

- #4179 - Unify disabled button states across collaborative editor
