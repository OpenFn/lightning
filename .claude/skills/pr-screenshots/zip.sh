#!/usr/bin/env bash
# Bundle a shoot.mjs output directory into a zip.
#
#   .claude/skills/pr-screenshots/zip.sh <shots-dir> <out.zip>
#
# Includes every PNG plus manifest.json and a captions.md (name, caption, URL
# path) so the zip makes sense on its own.
set -euo pipefail

dir="${1:?usage: zip.sh <shots-dir> <out.zip>}"
out="${2:?usage: zip.sh <shots-dir> <out.zip>}"
[[ -f "$dir/manifest.json" ]] || { echo "no manifest.json in $dir; run shoot.mjs first" >&2; exit 1; }

node -e '
const m = require(require("path").resolve(process.argv[1], "manifest.json"));
const lines = ["# Screenshots", ""];
for (const s of m) {
  const p = new URL(s.url).pathname + new URL(s.url).search;
  lines.push(`- **${s.file}**${s.caption ? ": " + s.caption : ""} (\`${p}\`)`);
}
require("fs").writeFileSync(require("path").join(process.argv[1], "captions.md"), lines.join("\n") + "\n");
' "$dir"

mkdir -p "$(dirname "$out")"
out="$(realpath -m "$out")"
rm -f "$out"
(cd "$dir" && zip -q -X "$out" ./*.png manifest.json captions.md)
echo "$out ($(du -h "$out" | cut -f1), $(ls "$dir"/*.png | wc -l) screenshots)"
