---
name: screenshots
description: Run Lightning locally with the demo.openfn.org data set and take screenshots of any page. Use when asked to screenshot the app, show what a page or change looks like, or capture UI for a PR, doc, or design review. Works from a bare Claude Code cloud container.
---

# Screenshots of a local Lightning

Two scripts live next to this file:

- `setup.sh` installs the toolchain, builds the app, seeds the **same data as
  demo.openfn.org**, and starts `mix phx.server` on :4000. It's idempotent.
- `shoot.mjs` logs in with Playwright and saves a PNG per page.

## Steps

```bash
# 1. Setup (about 10 min the first time, seconds after that). Prints user
#    emails, project ids and workflow editor paths at the end.
.claude/skills/screenshots/setup.sh            # add --reseed to reset the data

# 2. Shoot. Each arg is name=path or name=path@css-selector-to-wait-for.
P=<openhie-project id>; W=<OpenHIE Workflow id>
node .claude/skills/screenshots/shoot.mjs \
  --base http://localhost:4000 --email demo@openfn.org --out screenshots \
  projects=/projects \
  workflows=/projects/$P/w \
  editor=/projects/$P/w/$W \
  history=/projects/$P/history \
  settings=/projects/$P/settings
```

Then **open every PNG with Read and look at it** before handing it over. A
login page or a blank canvas means something went wrong.

Other `shoot.mjs` flags: `--password`, `--width`/`--height` (default 1440x900,
rendered at 2x), `--full` for full-page captures, `--wait <selector>` on every
page. It also lists any uncaught page errors at the end. `--base` and `--email`
default to `http://localhost:4000` and `demo@openfn.org`.

To click into something first (select a node, open a panel) or crop to one
component, use `--spec shots.json`. The format is in the header of
`shoot.mjs`. Example: select a job in the editor with
`{"click": ".react-flow__node:has-text(\"Transform data\")"}`. Every run also
writes `manifest.json`, which the `pr-screenshots` skill uses.

To send screenshots to the user, write them into the repo working directory or
the scratchpad (the Claude app can only open files there) and use
`SendUserFile`. Don't commit them.

## The demo data

`priv/repo/demo.exs` -> `Lightning.Demo.reset_demo/0` (`lib/lightning/demo.ex`)
-> `Lightning.SetupUtils.setup_demo(create_super: true)`. This is what resets
demo.openfn.org every night. `reset_demo` does nothing unless
`IS_RESETTABLE_DEMO=yes`, and it wipes the database first.

| user                | name          | role                                   |
| ------------------- | ------------- | -------------------------------------- |
| `demo@openfn.org`   | Amy Admin     | admin on openhie, owner of dhis2       |
| `editor@openfn.org` | Esther Editor | editor on openhie                      |
| `viewer@openfn.org` | Vikram Viewer | viewer on openhie                      |
| `super@openfn.org`  | Sizwe Super   | superuser, owner of openhie            |

Password for all of them: `welcome12345`.

Projects: **openhie-project** (OpenHIE Workflow: webhook -> 4 http jobs, with
one successful work order) and **dhis2-project** (DHIS2 to Sheets, with one
failed work order). Ids are random per seed, so `setup.sh` prints them.

Need different data (more projects, specific workflows)? Write a Kickstart
scenario (`bin/e2e.d/scenarios/README.md`) and load it with
`mix lightning.kickstart path/to/scenario.yaml`. It upserts, so it layers on top
of the demo data.

## What worked and what didn't

Learned getting this going in a fresh cloud container (Oct 2026).

**Didn't work / gotchas**

- **No Elixir in the image, and apt's is too old.** `.tool-versions` wants
  OTP 28 / Elixir 1.18. `setup.sh` pulls prebuilt binaries from builds.hex.pm
  into `/opt/beam`. You need `LANG=C.UTF-8` and `ELIXIR_ERL_OPTIONS=+fnu` or
  Elixir warns about latin1.
- **`bin/bootstrap` assumes asdf/mise.** The parts that matter are reproduced
  in `setup.sh` instead.
- **`enacl` fails with `sodium.h: No such file`.** It needs `libsodium-dev`.
  bin/bootstrap lists it, but it isn't in the image.
- **Postgres is installed but stopped,** and the `postgres` user has no
  password. `setup.sh` starts it and sets the password to `postgres` to match
  `config/dev.exs`.
- **Playwright can't find its browser.** The repo's `@playwright/test` wants
  chromium revision 1200; the container ships 1194 at `/opt/pw-browsers`.
  Don't run `playwright install` (it downloads a whole browser). `shoot.mjs`
  passes `executablePath: /opt/pw-browsers/chromium` instead (override with
  `CHROMIUM_PATH`).
- **There's no `chromium-cli` in the image,** which is why there's a custom
  driver.
- **Dev-only overlays show up in shots:** the Tidewave toolbar (bottom left,
  "Sign in") and LiveDebugger's bug button (bottom right). `shoot.mjs` hides
  `#tidewave-toolbar` and `#debug-button`.
- **The /projects greeting types itself out** (`TypewriterHook`), so an early
  shot catches "Click|". `shoot.mjs` waits until the text stops growing. The
  greeting also depends on the time of day ("Good evening, Amy!").
- **The git pre-commit hook runs `mix`.** Commit with the `/opt/beam` PATH
  exported, and not while a build holds the mix lock.

**Worked**

- `IS_RESETTABLE_DEMO=yes mix run priv/repo/demo.exs` to seed, then
  `mix phx.server`, then Playwright login via the `/users/log_in` form.
- Waiting for LiveView's `.phx-connected` plus a short network-idle wait was
  enough for every page tried: projects, workflows list, collaborative editor
  canvas, history, and settings.
- `bin/e2e start` is an alternative that runs the same `setup_demo` into a
  separate `lightning_test_e2e` DB on :4003, with snapshot resets. It still
  needs everything above to be installed first.
- If you just need production UI and not a branch, demo.openfn.org is
  reachable from the container: `--base https://demo.openfn.org`. It's public
  and reset nightly.
