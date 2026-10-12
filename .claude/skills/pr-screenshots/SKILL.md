---
name: pr-screenshots
description: Screenshot the UI a Lightning pull request changes, then either hand the user a zip of the images or post them as a comment on the PR (or both). Use when asked for PR screenshots, before/after shots of a change, or to "add screenshots to the PR". Usage /pr-screenshots <pr number | current> [zip | post | both] [--before-after]
---

# PR screenshots

Builds on the `screenshots` skill (`.claude/skills/screenshots/`). It runs the
PR's code locally with the demo.openfn.org data, shoots the pages the PR
touches, then does one or both of:

- **zip**: bundle the PNGs and send the zip to the user.
- **post**: host the PNGs on a `pr-screenshots/<pr>` branch and post (or
  update) one comment on the PR that embeds them.

If the user didn't say which, ask: zip, post, or both. Posting is visible to
everyone on the PR, so don't post unless they asked for it.

## 1. Find the PR and check out its code

- Get the PR with `mcp__github__pull_request_read` (`method: get`) for the head
  and base refs, and `method: get_files` for the changed files. "current"
  means the PR whose head is the branch you're on (`list_pull_requests` with
  `head: OpenFn:<branch>`).
- If you aren't already on the head branch, `git status` first. Don't discard
  uncommitted work; ask. Then `git fetch origin <head> && git checkout <head>`.

## 2. Run it

```bash
.claude/skills/screenshots/setup.sh
```

If a server is already running from a **different** checkout, restart it so it
serves this code: `lsof -ti:4000 -sTCP:LISTEN | xargs -r kill`, then run
`setup.sh` again. It recompiles, migrates, and prints the demo ids.

## 3. Decide what to shoot

Read the diff and choose the screens a reviewer would want to see. Show the
change itself: open the panel, select the node, trigger the state. Don't just
show the page it lives on. Rough map from code to screen:

| changed code | where to look |
| --- | --- |
| `assets/js/collaborative-editor/**` | workflow editor `/projects/$P/w/$W`, plus clicks (select a job with `.react-flow__node:has-text("…")`, open run panel, etc.) |
| `lib/lightning_web/live/workflow_live/**` | workflows list `/projects/$P/w` |
| `lib/lightning_web/live/run_live/**`, history components | `/projects/$P/history`, a run `/projects/$P/runs/<id>` |
| `lib/lightning_web/live/project_live/**` (settings) | `/projects/$P/settings` (and its tabs, as `#hash` or clicks) |
| `lib/lightning_web/live/dashboard_live/**` | `/projects` |
| credentials, profile, tokens | `/credentials`, `/profile`, `/profile/tokens` |
| admin (`/settings/...`) | log in as `super@openfn.org` |
| `assets/css/**`, shared components | a few representative pages |

If the change needs data the demo doesn't have, add it with a Kickstart
scenario (`bin/e2e.d/scenarios/README.md`, `mix lightning.kickstart`) rather
than clicking it together.

Write a spec file (format in the header of `shoot.mjs`) and give every shot a
`caption`, because the captions become the comment headings:

```bash
node .claude/skills/screenshots/shoot.mjs --spec /tmp/pr-shots/spec.json --out /tmp/pr-shots/out
```

`shoot.mjs` exits non-zero and prints `FAILED <name>` for any shot whose
selector didn't match. Fix the spec; don't drop the shot silently.

**--before-after:** shoot the base branch first with names prefixed
`before-`, then check out the head, restart the server, and shoot the same
spec with `after-` into the **same** out dir. `publish.sh` pairs
`before-X`/`after-X` side by side in a table. Re-seed (`setup.sh --reseed`)
only if the PR has migrations that change the demo data.

**Look at every PNG with Read** before you deliver anything. A login page, a
spinner, or an empty canvas means the wait or the steps are wrong.

## 4a. Zip

```bash
.claude/skills/pr-screenshots/zip.sh /tmp/pr-shots/out <scratchpad>/pr-<n>-screenshots.zip
```

The zip has the PNGs, `manifest.json`, and a `captions.md`. Send it with
`SendUserFile` (`display: attach`). It must sit in the scratchpad or the repo
working directory, because those are the only places the Claude app can open.
Don't commit it.

## 4b. Post to the PR

```bash
COMMIT_TRAILER="<session attribution line, if your instructions give one>" \
  .claude/skills/pr-screenshots/publish.sh <n> /tmp/pr-shots/out
```

This commits just the PNGs to `pr-screenshots/<n>`, built with git plumbing so
your working tree and the PR's diff are untouched. It pushes that branch and
prints the comment body (also saved to `out/comment.md`). Images are linked
by commit SHA, so re-running never breaks an older comment. Use `--dry-run`
to see the body without pushing.

Then post the body:

1. Look for an earlier one: `mcp__github__issue_read` (`method:
   get_comments`) on the PR, and find a comment containing
   `<!-- pr-screenshots -->`.
2. If there is one, replace it with `mcp__github__update_issue_comment`.
   Otherwise use `mcp__github__add_issue_comment`.
3. End the body with the attribution footer your instructions require, if any.

Give the user the comment link.

**If the push is refused** (cloud sessions are often only allowed to push the
session's own branch), don't work around it by committing PNGs to the PR's
branch, which would land them in the diff. Tell the user, hand over the zip
instead, and point them to the `github.access` page of `read_documentation`.

## Notes

- The demo data is public (it's what demo.openfn.org shows), so it's safe in
  a PR comment. Never screenshot pages showing real credentials or personal
  data. If a page shows a credential body, crop it out with `element`.
- The `pr-screenshots/*` branches are throwaway. Delete them once the PR is
  merged if the repo wants them tidy, but note that deleting one breaks the
  images in that PR's comment.
- The time-of-day greeting on `/projects` and the "today at" timestamps vary
  from run to run, so before/after shots of those won't match pixel for pixel.
