#!/usr/bin/env bash
# Host a shoot.mjs output directory on GitHub and print a PR comment body that
# embeds the images.
#
#   .claude/skills/pr-screenshots/publish.sh <pr-number> <shots-dir> [--dry-run]
#
# GitHub has no API for uploading images into comments, so the images are
# committed to a dedicated branch, pr-screenshots/<pr-number>, and the comment
# links them by commit SHA (so later re-runs never break old comments). The
# commit is built with git plumbing: nothing in the working tree, index or
# current branch is touched, and the PR's own diff stays clean.
#
# Re-running appends a new commit on that branch (the previous tip is the
# parent, so earlier comment links stay reachable).
#
# Env:
#   COMMIT_TRAILER  appended to the commit message (e.g. a session link)
#   REMOTE          git remote to push to (default origin)
#
# Output: the comment body on stdout (markdown), also saved to
# <shots-dir>/comment.md. Post it with the GitHub MCP tools; see SKILL.md.
set -euo pipefail

pr="${1:?usage: publish.sh <pr-number> <shots-dir> [--dry-run]}"
dir="${2:?usage: publish.sh <pr-number> <shots-dir> [--dry-run]}"
dry=false
[[ "${3:-}" == "--dry-run" ]] && dry=true
remote="${REMOTE:-origin}"
branch="pr-screenshots/$pr"
[[ -f "$dir/manifest.json" ]] || { echo "no manifest.json in $dir; run shoot.mjs first" >&2; exit 1; }

# owner/repo from the remote URL (https or ssh, with or without .git).
slug=$(git remote get-url "$remote" | sed -E 's#^(https?://[^/]+/|git@[^:]+:)##; s#\.git$##')

# Previous tip, if the branch already exists on the remote.
git fetch -q "$remote" "refs/heads/$branch:refs/remotes/$remote/$branch" 2>/dev/null || true
parent=$(git rev-parse -q --verify "refs/remotes/$remote/$branch" || true)

# One tree containing just this run's PNGs.
tree=$(
  for f in "$dir"/*.png; do
    printf '100644 blob %s\t%s\n' "$(git hash-object -w "$f")" "$(basename "$f")"
  done | git mktree
)
msg="Screenshots for PR #$pr"
[[ -n "${COMMIT_TRAILER:-}" ]] && msg+=$'\n\n'"$COMMIT_TRAILER"
commit=$(git commit-tree "$tree" ${parent:+-p "$parent"} -m "$msg")

if $dry; then
  echo "dry run: would push $commit to $remote $branch" >&2
else
  git push -q "$remote" "$commit:refs/heads/$branch"
  echo "pushed $commit to $remote $branch" >&2
fi

# Comment body. Shots named before-X / after-X are paired side by side.
node - "$dir" "$slug" "$commit" "$pr" <<'EOF' | tee "$dir/comment.md"
const [dir, slug, sha, pr] = process.argv.slice(2);
const m = require(require('path').resolve(dir, 'manifest.json'));
const img = (s, w) =>
  `<img src="https://github.com/${slug}/blob/${sha}/${s.file}?raw=true" alt="${s.name}"${w ? ` width="${w}"` : ''}>`;
const label = s => s.caption || s.name.replace(/^(before|after)-/, '').replace(/[-_]/g, ' ');
const out = ['<!-- pr-screenshots -->', '## Screenshots', ''];
const byName = Object.fromEntries(m.map(s => [s.name, s]));
const done = new Set();
for (const s of m) {
  if (done.has(s.name)) continue;
  const key = s.name.replace(/^(before|after)-/, '');
  const before = byName[`before-${key}`], after = byName[`after-${key}`];
  if (before && after) {
    out.push(`### ${label(after)}`, '', '| Before | After |', '| --- | --- |',
      `| ${img(before, 480)} | ${img(after, 480)} |`, '');
    done.add(before.name); done.add(after.name);
  } else {
    out.push(`### ${label(s)}`, '', img(s, 960), '');
    done.add(s.name);
  }
}
out.push(`<sub>Captured from a local build of this PR seeded with the demo data. ` +
  `Images live on the [\`pr-screenshots/${pr}\`](https://github.com/${slug}/tree/${sha}) branch.</sub>`);
console.log(out.join('\n'));
EOF
