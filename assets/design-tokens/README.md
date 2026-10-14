# Design tokens

The two JSON files here are the Figma variable exports, unedited. `build.ts`
turns them into Tailwind theme variables in `assets/css/design-tokens.css`.
Don't edit that CSS by hand.

## Update the tokens

1. Export the variables from Figma and replace `Light.tokens.json` and
   `Static.tokens.json`.
2. Rebuild the CSS:

   ```bash
   cd assets
   npm run design-tokens
   ```

3. Read the warnings it prints. Each one names a token it dropped and why.
4. Commit the exports and the CSS together. `test/design-tokens.test.ts` fails
   if the CSS doesn't match the exports.

## Class names

Every class carries `ds-`, so it can't collide with a plain Tailwind class. A
trailing `default` is dropped.

| Figma token                     | Classes                                                                               |
| ------------------------------- | ------------------------------------------------------------------------------------- |
| `bg/action/primary/default`     | `bg-ds-action-primary`                                                                |
| `text/subtle`                   | `text-ds-subtle`                                                                      |
| `icon/primary`                  | `text-ds-icon-primary`, `fill-ds-icon-primary`                                        |
| `border/action/primary/default` | `border-ds-action-primary`, `border-b-ds-action-primary`, `ring-ds-…`, `outline-ds-…` |
| `White`, `Black`, `Transparent` | every colour utility: `bg-ds-white`, `border-ds-transparent`                          |
| `space/xs`                      | `p-ds-xs`, `m-ds-xs`, `w-ds-xs`, `size-ds-xs` and other spacing utilities             |
| `gap/sm`                        | `gap-ds-sm` only                                                                      |
| `radius/md`                     | `rounded-ds-md`                                                                       |
| `border/lg` (width)             | `border-ds-width-lg`, `ring-ds-width-lg`, `outline-ds-width-lg`                       |
| font families                   | `font-ds-sans`, `font-ds-mono`, `font-ds-display`                                     |
| font weights                    | `font-ds-weight-medium` and the others                                                |
| text styles                     | `text-ds-type-body-lg` sets size, line height, letter spacing and weight              |

`space/` and `gap/` have different scales: `space/xs` is 8px, `gap/xs` is 4px.

The words `type`, `width` and `weight` let `cn()` tell a text style from a text
colour, and a border width from a border colour. Keep them.
