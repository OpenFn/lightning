# Design tokens

The Figma variables exports. `bin/design-tokens` turns them into Tailwind
classes, so don't use these files directly.

## Updating after a Figma change

1. In Figma, export the Colours collection (Light and Dark) and the Static
   collection, and replace the files here.
2. From the repo root, run `bin/design-tokens`.
3. Commit these files along with the two the script writes:
   - `assets/css/ui/tokens.css`, the classes (`bg-action-primary`, `p-sm`…)
   - `assets/js/utils/token-names.json`, so `cn()` knows those classes

Never edit the two generated files by hand. Rerun the script.

## What the script tells you

- **wrote … tokens**: done.
- **skipped …: no rule for it**: Figma has a new kind of token the script
  doesn't turn into classes yet. Nothing was half-added. To add it, write a rule
  in `bin/design-tokens` (see the comment at the top).
- **skipped …: redefines a Tailwind default**: Tailwind already has a class with
  that name, so the token isn't copied. Use Tailwind's class.
- **… has no MERGE_GROUPS entry**: someone added a rule for a new kind but not
  the line that tells `cn()` about it. The script stopped without writing
  anything. Add the line it names and run it again.

`Dark.tokens.json` isn't used yet: most of its colours are placeholders.
