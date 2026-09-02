# Adaptors on the fly: working context

**Branch:** `adaptors-on-the-fly`, PR [#4801](https://github.com/OpenFn/lightning/pull/4801). The PR targets `release-2.19.0`; the branch itself is based on `main` (see §5 for what that means).
**Worktree:** `/Users/stuart/Sourcecode/lightning/.claude/worktrees/adaptors-on-the-fly`. Run everything from there.
**Last updated:** 2026-09-14
**Operator reference:** [ADAPTORS.md](ADAPTORS.md) in this repo is the how-to for deployers. This document is the working record for whoever picks the branch up, and it stands on its own.

Every `file:line` below was checked against the tree on 14 Sep. Read the source at the citation rather than trusting the paraphrase.

---

## 1. What this branch is for

Lightning used to learn about adaptors once, at Docker build time. The adaptor list, every credential schema and every icon were baked into the image by `mix lightning.install_schemas` and `mix lightning.install_adaptor_icons`. A new adaptor, or a new version of an existing one, meant waiting for a Lightning rebuild and a redeploy before anyone could pick it.

This branch moves all of that to runtime. Lightning keeps its own catalogue of adaptors in Postgres and refreshes it from npm on a timer, so new adaptors, new versions, icons and credential schemas appear on a running instance without touching the deployment.

Two things define "working":

- The adaptor picker matches npm within one refresh interval (an hour by default), without a redeploy.
- An airgapped or offline instance still boots with a catalogue you loaded deliberately, and keeps serving it.

The second is not an afterthought. Several OpenFn deployments sit behind restricted networks, and this change moves the network requirement from build time to run time: an image build no longer needs npm, jsDelivr or GitHub, but a running instance does. Anywhere the build network had outbound access and the runtime network does not, this breaks unless the operator uses the offline snapshot route. That is why the snapshot/dump/import tooling exists, and why most of the outstanding work in §7 is about behaving sensibly when the upstream cannot be reached.

---

## 2. How the pieces fit

Everything lives under `lib/lightning/adaptors/`, with `lib/lightning/adaptors.ex` as the public facade.

**The facade** (`lib/lightning/adaptors.ex`). Every function that talks to a running process takes the supervisor instance as an optional first argument, defaulted from `Config.default_instance()`. The public functions are `packages/1`, `schema/2`, `resolve_name/2`, `icon/3`, `catalogue/1`, `fetch_adaptor/2`, `ensure_loaded/1`, `parse_spec/1`, `valid_format?/1`, `to_wire/2`, `refresh/1,2`, `refresh_package/2`, `refresh_icons/1`, `icon_meta/2`, `subscribe_to_updates/1`, plus two delegates used by the snapshot tooling, `seed_from_file/2` and `dump_to_file/2` (`adaptors.ex:370, 376`). Reads return `{:ok, _}` or `{:error, _}`; `resolve_name/2` and `parse_spec/1` were the last two hiding a failure behind a bare value and were converted in `220f7a4240`, with their callers moved in the same commit. Not everything is a tuple: `valid_format?/1` returns a boolean, and `ensure_loaded/1`, `refresh_package/2`, `subscribe_to_updates/1` and `refresh/2` without `await: true` return a bare `:ok` on success. `ensure_started/1` is on `Lightning.Adaptors.Supervisor` (`supervisor.ex:47`), not the facade.

Configuration is under `config :lightning, Lightning.Adaptors` with keys `:strategy`, `:refresh_interval` (ms), `:first_load_timeout` (ms), `:cache_timeout_ms` and `:icon_path` (`adaptors.ex:20-30`); defaults live in `Lightning.Adaptors.Config`. Only some of those have environment variables (§4). `first_load_timeout` does not; it is application config only.

**The store** (`adaptors/store.ex`). A per-node Cachex cache with no TTL, backed by Postgres through `Catalogue`. Reads never write to the catalogue; the scheduler is the only writer. Cache coherence between nodes comes from change broadcasts: `Lightning.Adaptors.Invalidator` subscribes to the source's PubSub topic and drops the affected keys on `{:changed, name, source}`, and `Lightning.Adaptors.NodeMonitor` calls `Store.warm_from_repo/1` when it sees a `:nodeup`, so a node that missed broadcasts during a partition re-warms from Postgres when the other node comes back. `nodedown` is deliberately a no-op.

**The catalogue** (`adaptors/catalogue.ex`) is the Ecto layer over two tables, `adaptors` and `adaptor_versions`. Read paths for the picker and credential types apply the exclusion list (`@excluded_names`, `catalogue.ex:52-55`) and the `deprecated == false` filter through `active_adaptors/1` (`:336-341`). The resolve paths, `get_adaptor/2` (`:111-113`) and `list_versions/2` (`:119-127`), are deliberately unfiltered so a job already pinned to an excluded or deprecated adaptor keeps validating. Write paths apply no filter at all; whatever the strategy lists gets written.

**Source strategies.** `Lightning.Adaptors.NPM` (default) and `Lightning.Adaptors.Local`. A strategy provides `list_adaptors/0` plus per-adaptor metadata, schema and icon fetches. npm reads the org listing `GET /-/user/openfn/package` as the authoritative name list and uses npm search only for cheap version lookup, with a per-name packument fallback for names search misses (`npm/registry.ex` moduledoc). The reason for two calls: search omits deprecated packages, and we need to know about those to keep already-pinned jobs working. Change detection in the scheduler diffs each upstream `{name, latest_version}` pair against the rows already in the database (`scheduler.ex:505`, `fetch_if_changed/4`).

Local mode stores each package's real semver from `package.json` in the database, but the projection served to the picker replaces it with the literal `local` (`store.ex:341-342`), so every adaptor shows version `local` in the UI while `SELECT latest_version FROM adaptors` shows real versions.

**The scheduler** (`adaptors/scheduler.ex`) is a cluster singleton elected by a Postgres advisory lock (HighlanderPG wraps the scheduler child at `supervisor.ex:124-131`), running a refresh cycle on a timer. Children are supervised `one_for_one` (`supervisor.ex:134`) so a crash in one component does not take the rest down.

**Naming and instances.** Every child, cache, PubSub topic and lock name derives from the supervisor's `:name` via `Module.concat` or string interpolation (`supervisor.ex:90-93, 178-234`), defaulting to `Config.default_instance()`. That is what lets several instances run in one BEAM, which is how the tests isolate themselves, and how `Supervisor.ensure_started/1` (`:46-55`) can treat `{:error, {:already_started, pid}}` as `{:ok, pid}`. `ensure_started/1` also starts the named Finch pool if Tesla is configured for Finch and nothing is registered under that name yet (`ensure_finch/0`, `:60-69`), which is what the out-of-band paths (mix tasks, `bin/lightning eval`, isolated tests) need. In normal boot the subsystem is an ordinary child of `Lightning.Supervisor` after `Lightning.Repo` (`application.ex:170`). On the out-of-band path it starts inside `Ecto.Migrator.with_repo` (`setup.ex:45-52`) because the scheduler takes its advisory lock as soon as it boots and needs the Repo up first.

**HTTP.** `GET /adaptors/catalogue` (`adaptor_controller.ex`, `router.ex:121`): session-authenticated, not project-scoped, ETag from a `(stamp, count)` pair, `cache-control: private, no-cache`, `vary: Cookie`, 304 on a matching `If-None-Match`; 503 with `{"error": "adaptor catalogue unavailable"}` on any `{:error, _}`; 200 with `{"data": []}` when the catalogue has loaded and is genuinely empty. `GET /adaptors/icons/:name/:filename` (`adaptor_icon_controller.ex`, `router.ex:70-72`) is public, content-addressed on the first eight characters of the sha, served with `public, max-age=31536000, immutable`, a `default-src 'none'; sandbox` CSP and `nosniff` (`lightning_web/utils.ex:174-187`). A stale sha 302-redirects to the current URL with `Cache-Control: no-store`; an unknown adaptor or removed icon is a 404; a catch-all clause at `:107` returns 404 for anything else. Adaptor names never build a filesystem path directly: `icon_meta/2` looks the name up in the catalogue first, so a traversal attempt is simply `:not_found`. `d65c3e61dc` added the explicit rejection of names that could escape the icon cache directory, and `001161f66e` annotated those checks.

The editor fetches its adaptor list over HTTP (`assets/js/collaborative-editor/api/adaptors.ts`), not the channel. The channel still has a `request_adaptors` handler (`workflow_channel.ex:109-117`) that collapses `{:error, _}` to an empty list (`:993-997`); nothing in `assets/js` calls it outside tests (see §11).

**Live update.** `Lightning.Adaptors.ChannelBroadcaster` coalesces a burst of `{:changed, ...}` into one `adaptors_updated` push every 250ms (`channel_broadcaster.ex:19, 62-83`). The channel forwards it (`workflow_channel.ex:726`) and the editor reloads the list itself. `Lightning.Credentials.SchemaReconciler` listens for the same event (§4, migrations).

### The first-load gate

A cold instance has an empty catalogue, and a caller reading it must not conclude "no adaptors exist" when the truth is "we have not looked yet". `Store.gated/2` (`store.ex:251-259`) wraps the reads: run the read; if the result is empty and the catalogue has never loaded, wait for a refresh and read once more; otherwise return what came back. "Empty" is `{:error, :not_found}`, `{:ok, []}` or `{:ok, {_stamp, []}}` (`empty?/1`, `:261-264`). Only an empty result pays for the `loaded?` query.

Five reads go through it (`store.ex:69, 102, 158, 187, 213`): `schema/2`, `icon/3`, `packages/1`, `catalogue/1`, `icon_meta/2`. `fetch_adaptor/2` and `ensure_loaded/1` use the same wait through `first_load/1`.

"Has it ever loaded" is answered by `loaded?/1` (`store.ex:269-272`), which is true if either:

- `Catalogue.max_checked_at(source)` is non-nil, meaning at least one row exists for this source. `checked_at` is stamped on every adaptor the cycle saw, changed or not (`Catalogue.upsert_adaptor/1` and `touch_checked_at/2`), so `max_checked_at` is nil only when there are zero rows. A previous boot or a seed import both count. Nothing clears it except `delete_all_for_source/1`.
- `Scheduler.completed?/1` is true. The scheduler sets it when a cycle finishes as `{:ok, %{listed: 0, errors: 0}}` (`scheduler.ex:271-272`) and nothing ever resets it. It is a field in the scheduler's process state (initialised `false` at `:165`), so a scheduler restart loses it and costs one more refresh, not a loop. `completed?/1` answers `false` when the scheduler is unreachable (`:137-142`). A cycle that listed anything at all does not set it; rows answer for those.

The second clause landed in `5f70ab91d2` to fix a real loop. Before it, a cycle that completed and wrote no rows left `max_checked_at` nil, so every read started another full refresh, forever. There were four ways to reach that state: the upstream listing genuinely empty; every per-adaptor fetch failing; every fetch succeeding and every upsert failing (which `dcbd4dd8c1` fixed separately, below); and local mode pointed at an empty directory. Filters cannot cause it because they only apply on read. The moduledoc at `store.ex:14-23` describes the intended contract: a first-load gate, not a health check.

The wait is `Config.first_load_timeout/0`, defaulting to 90 seconds (`config.ex:16`). It was 60 and went up in `220f7a4240` because a cold npm listing plus a per-adaptor fetch of the whole org does not reliably finish inside a minute. `Store.await_refresh/1` (`store.ex:284-292`) is a `GenServer.call` to the scheduler with that timeout; the scheduler stashes the caller in `waiters` (`scheduler.ex:351-358`) and replies to everyone when the refresh task finishes (`:261-275`). On a client-side timeout the store returns `{:error, :timeout}`; if the scheduler is not running, `{:error, :unavailable}`. After a refresh resolves without an error, `first_load/1` re-reads `loaded?` rather than trusting the refresh counts, because a failed cycle can land on rows a seed already wrote (`:275-282`).

The gate lives in `Store` rather than the facade on purpose: reads flow `Adaptors → Store → Catalogue`/`IconCache`, and the blocking belongs at the layer that knows whether it found anything. Putting it in the facade would have meant two competing readiness mechanisms, which is also why `get_schema`/`fetch_schema` were collapsed back into one `schema/2`.

### How the scheduler treats a missing schema

The same "we know" versus "we don't know yet" question exists one level down, for credential schemas, and was answered deliberately there. `NPM.Schema.schema/2` returns `{:ok, {nil, nil}}` only for a 404 on `configuration-schema.json` at the pinned version (`npm/schema.ex:35`); every other outcome is `{:error, _}`, and the moduledoc (`:8-10`) says the split exists so a transient failure is never mistaken for genuine absence. A whole-package 404 is `{:error, :not_found}` from `Registry.get_packument/1`.

What gets persisted is only `schema_data` (nullable); there is no column for which of the three states a row is in. Retry is inferred at tick time in `fetch_if_changed/4` (`scheduler.ex:505-541`) from `schema_data`, `updated_at` and a one-hour grace window (`@schema_grace_ms`, `:33`):

- has a schema, same version: skip, touch `checked_at` only.
- no schema, same version, `updated_at` within the hour: ask again. A repeated nil touches `checked_at` but not `updated_at`, so the clock runs from the last real change.
- no schema, same version, `updated_at` older than an hour: stop asking. The persisted meaning of "we have given up" is literally `schema_data IS NULL AND updated_at < now() - 1h`. There is no marker.

Consumers only see `has_schema: not is_nil(schema_data)` on `package_meta` (`catalogue.ex:23-31`), so nothing downstream can tell "confirmed absent" from "still inside the retry window". `keep_stored_schema/2` (`:552-560`) carries a previous version's schema forward when a version bump comes back without one, because jsDelivr may not have mirrored it yet. The operator path `refresh_package/2` (`force_refresh_one/3`, `:745-769`) does not do this and takes upstream as-is, so it is the only route by which a genuine schema removal lands.

The scheduler's tick summary log is `Adaptors[<source>]: refresh tick listed=N changed=N touched=N fetched=N icons=N healed=N not_modified=N errors=N duration=Nms` (`scheduler.ex:480-486`). Since `dcbd4dd8c1`, `errors = fetch_errors + (changed - persisted)` (`:477`), so an adaptor that fetched fine but failed to write counts as an error and a systemic write failure can no longer report a clean cycle. `touched = listed - changed - fetch_errors`.

---

## 3. What happens when npm cannot be reached

This is the behaviour a Services person or a client admin will ask about, and one claim in an earlier handoff is now false, so it is spelled out here.

- Boot is never blocked. The scheduler runs the first refresh in the background; the app serves pages while it does.
- With a populated catalogue, a failed refresh writes nothing and leaves rows alone. The picker, credential forms and validation keep working from the existing rows. The log shows `Scheduler: list_adaptors failed: <reason>` and a tick summary with `errors=1 changed=0`. The next tick retries. Recovery needs no restart.
- If only GitHub is unreachable, metadata still lands and icons are skipped that tick (`fetch_icons failed ... persisting records without icons`) and retried next tick.
- A single broken adaptor (bad packument) is skipped with a `fetch_adaptor(<name>) failed` warning, everything else lands, `errors=1`.
- With an empty catalogue and no upstream, reads that hit the gate wait up to 90 seconds. This is the part that changed on 14 Sep: `GET /adaptors/catalogue`, the credential form's type list, icon lookups, `Job` validation and `AdaptorService.install/2` all now block for the first-load timeout on a cold instance before they fail. The old statement "HTTP is served immediately regardless of catalogue state" was true before `220f7a4240` and is not true now. Do not let it into anything customer-facing without re-checking §7.2.
- After the timeout: `GET /adaptors/catalogue` is 503, the editor shows "Couldn't load adaptors. Please try again." with a Retry button, workflow save is rejected with "adaptor catalogue is not ready yet, try again shortly" (`job.ex:157-172`; the channel-side string is "The adaptor catalogue is still loading. Try again shortly.", `workflow_channel.ex:1247`), the credential form crashes (§7.3), and `install/2` returns `{:error, {:catalogue_unavailable, reason}}`.
- An imported snapshot survives the hourly refresh. A failed refresh does not wipe it.
- There is no switch that turns the subsystem off. `ADAPTORS_REFRESH_INTERVAL_SECONDS=0` disables the timer, after which the catalogue changes only on import or manual refresh. With the timer off and an empty catalogue, boot logs a warning pointing at ADAPTORS.md's offline section (`scheduler.ex:219-223`); with the timer on it logs `catalogue is empty at boot — refreshing now` (`:215-217`).

---

## 4. Deployment surface

### New environment variables

All read in `lib/lightning/config/bootstrap.ex` (`:997-1083` for the `ADAPTORS_*` block).

| Variable | Purpose | Default |
| --- | --- | --- |
| `ADAPTORS_STRATEGY` | Where the catalogue comes from: `npm` or `local` | `npm` |
| `ADAPTORS_LOCAL_REPO` | Path(s) to an adaptors monorepo checkout (the repo root, not `packages/`), comma-separated; first match wins on a name collision, and the log names every shadowed package on every scan | unset |
| `ADAPTORS_ICONS_PATH` | On-disk icon cache directory | `<tmp>/lightning/adaptor_icons` (`config.ex:15`, resolved at call time so a release does not bake in a build-time tmp path). The official image sets `/app/priv/adaptor_icons` in the Dockerfile |
| `ADAPTORS_REFRESH_INTERVAL_SECONDS` | Refresh cadence; `0` disables scheduled refreshes | `3600` |
| `ADAPTORS_NPM_REGISTRY_URL` | npm registry | `https://registry.npmjs.org` |
| `ADAPTORS_NPM_JSDELIVR_URL` | CDN credential schemas are read from | `https://cdn.jsdelivr.net` |
| `ADAPTORS_NPM_GITHUB_URL` | Raw host icons are read from | `https://raw.githubusercontent.com` |
| `ADAPTORS_NPM_GITHUB_REF` | Git ref of `OpenFn/adaptors` icons come from | `main` |
| `ADAPTORS_NPM_HTTP_TIMEOUT` | Per-request receive timeout, ms | `30000` |

All three upstreams are public, unauthenticated GETs. No tokens needed. An internal npm mirror works by setting the three `ADAPTORS_NPM_*_URL` variables and leaving the strategy as `npm`.

### Removed and deprecated

- **`SCHEMAS_PATH`: removed.** Delete it from deployment config. No references remain in `lib/` or `config/`.
- **`ADAPTORS_REGISTRY_JSON_PATH`: removed.** Same.
- `LOCAL_ADAPTORS=true` still works and warns "LOCAL_ADAPTORS is deprecated, use ADAPTORS_STRATEGY=local instead." (`bootstrap.ex:1063`), but only when `ADAPTORS_STRATEGY` is unset and `LOCAL_ADAPTORS` is the thing selecting local mode.
- `OPENFN_ADAPTORS_REPO` still works and warns "OPENFN_ADAPTORS_REPO is deprecated, use ADAPTORS_LOCAL_REPO instead." (`:1083`), only when local mode is on and `ADAPTORS_LOCAL_REPO` is unset.
- `ADAPTORS_STRATEGY=local` with no repo path at all fails boot with "ADAPTORS_STRATEGY is set to local, but neither ADAPTORS_LOCAL_REPO nor the deprecated OPENFN_ADAPTORS_REPO is set." (`:1030`).
- `ADAPTORS_PATH` is unchanged and unrelated (`bootstrap.ex:235`, default `./priv/openfn`). It is where the worker installs packages for execution.

### Migrations

Three, all required, forward-only, no backfill. `git diff main --name-only -- priv/repo/migrations` shows exactly these:

- `20260514150000_create_adaptors.exs` creates `adaptors` and `adaptor_versions` (including the `deprecated` boolean).
- `20260827084128_add_adaptor_catalogue_indexes.exs` indexes `adaptors.updated_at` and `adaptor_versions.inserted_at`.
- `20260907112954_widen_credentials_schema.exs` widens `credentials.schema` from varchar(40) to varchar(100), for full package names.

Existing credentials' short schema names (`http`) are rewritten to full package names (`@openfn/language-http`) at runtime by `Lightning.Credentials.SchemaReconciler`, a GenServer that runs once on start and again on every `adaptors_updated` broadcast, calling `Credentials.reconcile_legacy_schema_names/1` (`credentials.ex:606`). It only touches rows whose `schema` does not start with `@`, so it is idempotent; it does not bump `updated_at` and writes no audit events. A short name the catalogue cannot resolve is left alone. The UI still shows the short name; anything reading the database or the provisioning payload directly sees the long form.

### Build changes

`mix lightning.install_schemas` and `mix lightning.install_adaptor_icons` are deleted (`lib/mix/tasks/install_schemas.ex`, `install_adaptor_icons.ex`) and their `RUN` lines are gone from `Dockerfile` and `Dockerfile-dev`, along with the `COPY priv/schemas` and `ENV SCHEMAS_PATH` lines. RUNNINGLOCAL.md lost 74 lines about them. `bin/bootstrap` never called either task, so it is unchanged. A fork or custom build script calling those tasks will fail.

The Dockerfile sets `ENV ADAPTORS_ICONS_PATH=/app/priv/adaptor_icons` (`:118`) and creates and chowns the directory to the runtime user (`:127`). `docker-compose.yml` mounts a named volume `adaptor_icons` there (`:15, :43, :74`). Anything else on ephemeral storage re-downloads icons on every restart.

### Offline / airgapped

Full procedure in ADAPTORS.md § "Running without internet access". Short version, on an online instance:

```sh
mix lightning.adaptors.dump --path snapshot.json
tar czf icons.tar.gz -C "$ADAPTORS_ICONS_PATH" .
```

Or, with no populated instance anywhere, build from npm with no database: `mix lightning.adaptors.snapshot --path snapshot.json`. Without `--path` it writes `adaptor_registry_cache.json` under `priv`. It produces no icons.

Offline:

```sh
mkdir -p "$ADAPTORS_ICONS_PATH" && tar xzf icons.tar.gz -C "$ADAPTORS_ICONS_PATH"
mix lightning.adaptors.import --path snapshot.json --replace
```

`dump` and `import` both take `--source npm|local` (default `npm`) for moving a local-mode catalogue. On a release image: `bin/lightning eval 'Lightning.Release.dump_adaptors("…")'` and `Lightning.Release.seed_adaptors("…", replace: true)` (`release.ex:50, 72`). There is no release-image equivalent of `snapshot`; building a cold-start snapshot needs a source checkout with Mix. Plan for that if a client is airgapped and there is no populated instance to dump from.

**The snapshot carries icon metadata, not icon bytes.** Copy the icons directory separately or icons are silently missing. That is the most likely airgapped mistake.

Icons on disk are laid out as `<ADAPTORS_ICONS_PATH>/<source>/<name>/<shape>.<sha8>.<ext>`. Bytes on disk whose hash does not match the catalogue row are refused and the mismatch is cached as an error until the row's sha changes (`icon_cache.ex` moduledoc), so a hand-edit of the icon directory does not take and is not re-fetched on every request either.

---

## 5. What has landed

41 commits off `main` as of 14 Sep, 31 of them adaptor work. Against `release-2.19.0`, the PR's target, it is 36 commits: five of the ten non-adaptor commits are already on that branch (see §12).

**Foundation (25-31 Aug).** `32b38a7e68` added the data model, the Postgres store, the source strategies and the refresh scheduler. `4df07659e6` served icons and the catalogue over HTTP and wired the editor up. `69f6595ed2` cut every caller over to the `Lightning.Adaptors` facade and deleted the old registry. `ff55f4cd7c` moved the supervision to `one_for_one`.

**Hardening (2-8 Sep).** `4348ac2d15` added ADAPTORS.md and made the snapshot carry icon metadata so an airgapped mirror can be rebuilt. `790087de3f` cached the catalogue projection through the store. `4217880b62` made the npm org listing authoritative and hid deprecated adaptors from the pickers. `67f93a8d09` fixed a leaked tick chain in `refresh_now` and tightened per-adaptor fetch timeouts. `b76007fb18` stopped the supervisor crash-looping on a bad boot-time DB read. `9bcb43826a` gave schema-less adaptors an empty schema instead of crashing. `385024ef34` added the empty-catalogue boot warning and made the refresh interval configurable.

**Security and ops (10-11 Sep).** `d65c3e61dc` rejected adaptor names that could escape the icon cache directory; `001161f66e` annotated the traversal checks; `7d51f345bb` served icon content types from literals. `b010fbb804` made the scheduler take its interval and the empty-catalogue warning as opts. `8f95c205bf` gave the icon cache a fixed path in the image and a named volume in compose. `f6325ee457` renamed the refresh interval variable from `_MS` to `_SECONDS`: the default is an hour and every other recurring tick in the app is configured in seconds or coarser; milliseconds stay the internal unit.

`0007277c06` started the adaptors subsystem from the out-of-band setup commands. What prompted it: credential validation resolves adaptor names through `Lightning.Adaptors`, and nothing under `mix run --no-start` or `bin/lightning eval` had ever started it, so a colleague reproducing an unrelated bug hit an opaque `:persistent_term` `ArgumentError`. `Lightning.Setup.setup_user/3`, `Lightning.Demo.reset_demo/0` and `mix lightning.kickstart` all shared the gap; the fix routed all three through `with_minimum_setup/1` (`setup.ex:42`) and made `Supervisor.ensure_started/1` tolerate an already-running instance. It also fixed a real bug on the way past: `ensure_minimum_setup` checked for PubSub with `Process.whereis(mod)`, the module name `Phoenix.PubSub`, instead of the `Lightning.PubSub` name it registers under, so it matched an unrelated `:pg` scope and never actually verified PubSub was up. The fix is `Process.whereis(Keyword.get(opts, :name, mod))`.

**The first-load work (14 Sep)**, the source of most of §7:

- `e27931777e`: start Finch when the adaptors supervisor starts on its own, so the out-of-band paths have an HTTP pool (fixes Tesla "unknown registry" errors from setup commands, demo reset and isolated tests).
- `220f7a4240`: move the readiness gate into `Store`, gate every catalogue read on the first load, convert `resolve_name/2` and `parse_spec/1` to tuples, delete `get_adaptor/2`, update the `Credential`, `Job` and `AdaptorIconController` callers, raise the first-load timeout from 60s to 90s.
- `dcbd4dd8c1`: count the adaptors a refresh tick failed to write (the `errors` formula in §2).
- `5f70ab91d2`: settle the first-load gate on a source that lists no adaptors, via `Scheduler.completed?`.
- `931f16a020`: stop reporting an unreachable catalogue as a refused adaptor. `AdaptorService.known?/1` is gone, replaced by a three-way split in `install/2` (`adaptor_service.ex:311-336`): `{:ok, _}` installs, `{:error, :not_found}` gives `:adaptor_not_permitted`, and any other error gives `{:error, {:catalogue_unavailable, reason}}`. `MetadataService` reports `adaptor_catalogue_unavailable` separately from `no_matching_adaptor` (`metadata_service.ex:128, 131`).

A code review on 14 Sep confirmed the three items the previous handoff asked for are done and tested: the zero-row retry loop, the silently dropped upserts, and the `known?/1` policy-versus-technical confusion. The facade conversion has no stragglers; `get_adaptor/2` and `resolve_package_name/1` have no remaining callers.

### What a user sees differently

- New versions appear within one refresh interval, or immediately on a manual refresh, with no page reload in an open editor (about a second after the refresh lands).
- The editor has a loading state ("Loading adaptors…") and a failure state ("Couldn't load adaptors. Please try again." with Retry). Previously the list was just there.
- Only adaptors that actually have a credential schema appear as credential types. Before, the list came from the on-disk schema dump.
- Deprecated adaptors are hidden from the picker and the credential type list. Jobs pinned to one keep validating and running.
- New superuser page, Settings → Maintenance (`/settings/maintenance`, `maintenance_live/index.ex`), with Refresh Adaptor Registry (flashes "Adaptor refresh queued.", fire-and-forget) and Refresh Adaptor Icons (flashes "Icon refresh started." then "Icon refresh complete — N updated, M unchanged."; can take up to two minutes). A non-superuser is redirected to `/projects`.
- New failure message on workflow save during a cold start (§3).
- "Adaptors in this project" in the editor is derived client-side from the open workflow's jobs (`useAdaptors.ts:155-166`). An unsaved adaptor counts; adaptors used elsewhere in the project but not in this workflow no longer appear.
- `GET /images/adaptors/adaptor_icons.json` and the `request_project_adaptors` channel event are gone.

---

## 6. Decisions already taken

These are settled. They are here so the reasoning survives, and so nobody relitigates them by accident while working §7.

- **A credential save during a catalogue outage stays quiet and self-healing.** `resolve_schema_name/1` (`credential.ex:112-126`) stores the short name on `{:error, _}` rather than adding a changeset error, because the alternative blocks every credential save whenever the catalogue cannot answer, and the short form is a shape `get_schema/1` and the reconciler already handle. Adding the error also broke an unrelated test that only checks the 40-character length error (`credential_test.exs:100`), a fair preview of how widely it lands. The inconsistency with `Job` is noted in §7.3 and is about the other two surfaces, not this one.
- **`AdaptorService` reports a technical failure as one.** An unreachable catalogue gives `{:error, {:catalogue_unavailable, reason}}`, not `:adaptor_not_permitted`. "Not permitted" reads as a policy decision and sends whoever is debugging a failed install to the allowlist when the real problem is a timeout.
- **The first-load gate is a first-load gate, not a health check.** Once a source has ever loaded, `loaded?` answers true permanently. A catalogue that loaded in March and has silently stopped updating looks exactly as healthy as one refreshed a minute ago. Staleness is a separate concern with its own alerting, and it is not built.
- **The "a cycle completed" flag lives in scheduler memory, not a row.** Losing it on restart costs one refresh, not a loop, so it did not need persisting. §7.1 is about what sets the flag, not where it lives.
- **A zero-row cycle is a legitimate outcome, not a failure, at least for `:local`.** That is what `5f70ab91d2` encodes. Whether it holds for `:npm` is §7.1.
- **The npm org listing is authoritative, not npm search.** Search omits deprecated packages, and we need those to keep already-pinned jobs validating and running.
- **Deprecated adaptors are hidden, not removed.** They stay in the database and stay resolvable. Production has been checked and has no jobs on deprecated adaptors.
- **The icon cache path is set in the Dockerfile, not in bootstrap code.** Anyone operating Kubernetes is expected to know they need a PVC at that path.
- **The refresh interval is configured in seconds.** See `f6325ee457` in §5.

---

## 7. Outstanding items

Ordered by how much they matter. The first four are design calls for Stu, not bugs to hand straight to an agent; each has enough here to make the call without re-reading the code.

### 7.1 An empty npm listing latches "loaded" forever

**Where:** `scheduler.ex:271-272`, `store.ex:269-272`.

`Scheduler.completed?` flips true on `{:ok, %{listed: 0, errors: 0}}` and never flips back. For npm, `Registry.list_adaptors/0` returns `{:ok, []}` whenever `GET /-/user/openfn/package` answers 200 with a map holding no `@openfn/language-*` keys (`scoped_package_names/0`, `npm/registry.ex:145-161`). A non-200 is `{:error, {:http_status, status}}` and a transport failure is `{:error, reason}`, so those do not latch. But a mistyped `ADAPTORS_NPM_REGISTRY_URL` that lands on a server answering 200 with `{}`, an empty internal mirror, or an npm incident returning an empty body all look exactly like "no adaptors exist". For local, a configured root with no `packages/` directory logs a warning and contributes nothing (`local.ex:131-146`), so a mis-typed `ADAPTORS_LOCAL_REPO` latches the same way; only a completely unset path is an error (`:106-114`).

After one such tick on an instance with no rows, three things go wrong at once:

- `GET /adaptors/catalogue` answers 200 with `{"data": []}` instead of 503, so the editor shows an empty picker with no error and no Retry button.
- `Job.validate_known_adaptor` (`job.ex:157-172`) says "is not a recognised adaptor" instead of the retryable "catalogue is not ready yet". `readiness_test.exs:202-209` pins the underlying behaviour: `fetch_adaptor/2` returns `{:error, :not_found}` when the load lists nothing.
- `AdaptorService.install/2` answers `{:error, :adaptor_not_permitted}`, the exact wrong answer `931f16a020` set out to remove, arriving by the other door.

The tension was flagged before the fix went in: an empty listing is a legitimate outcome for `:local` (the directory really is empty) and essentially never a legitimate one for `:npm`. The latch was written source-agnostic.

**Options, cheapest first.**

1. Restrict the latch to `:local`. One guard on the `match?` at `scheduler.ex:272` using `state.source`. npm keeps the old loop behaviour on an empty listing (every read waits 90s and returns `:not_ready`), which is at least visible. Smallest diff; leaves "what does an empty npm listing mean" unanswered.
2. Require the source to have listed something non-empty at least once before the latch can set. Does not help a cold instance against a broken mirror, which is the case that matters.
3. Have the strategies distinguish "listed successfully, nothing there" from "could not list" at the boundary, mirroring what `NPM.Schema` already does for schemas (a 404 is knowledge, a timeout is not). For npm that means deciding whether a 200 with no matching keys is knowledge; the honest answer is probably that it is not, for an org that has hundreds of packages, so npm would return `{:error, :empty_listing}` and never latch. Most consistent with a distinction the codebase already makes; most work, since it touches the strategy behaviour, both implementations and their tests.

**Related:** `refresh_all/0` in `lib/mix/tasks/lightning.adaptors.refresh.ex:46-48` exits 2 on `{:ok, %{listed: 0}}` with "Refresh completed but the source listed no adaptors." while `Scheduler.completed?` treats the same cycle as a successful first load. Pick one reading, or the operator gets a failing exit code for a state the app has decided is fine. Option 3 resolves this for free.

**Reproducing it:** point `ADAPTORS_NPM_REGISTRY_URL` at a host that answers 200 with `{}` on `/-/user/openfn/package`, start against an empty database, and watch `GET /adaptors/catalogue` return 200 with an empty list rather than 503.

### 7.2 Gating the catalogue read puts 90 seconds on paths that used to answer immediately

**Where:** `store.ex:251-259`, with `catalogue/1` at `:187` and `icon_meta/2` at `:213`.

Both now go through `gated/2`. On a cold instance whose refresh is failing, `GET /adaptors/catalogue` holds the request for the full 90 seconds before returning 503. Every editor session opened during the cold window holds a request process for a minute and a half. The same wait applies to the credential form's type list (`credential_form_component.ex:1178`), icon requests (`adaptor_icon_controller.ex:85, 123`), the channel's `request_adaptors` handler, and workflow save: `Session.save_workflow/2` calls `ensure_loaded` (`session.ex:387`) and its own `GenServer.call` timeout is `first_load_timeout + 10s` (`:243-247`) precisely so it outlives the gate.

**Related leak.** When the caller's `GenServer.call` times out first, the scheduler does not know; it still holds the `from` in `waiters` and, when the refresh eventually finishes, `GenServer.reply/2` delivers `{ref, result}` straight into the caller's mailbox. This pre-dates the branch but used to be reachable only from `fetch_adaptor`/`ensure_loaded`; it now reaches every caller of the five gated reads. Where that lands:

- Controllers: harmless, the request process is gone.
- `Collaboration.Session`: harmless, it has a catch-all `handle_info/2` (`session.ex:443`).
- LiveViews hosting the credential form component: the stray message goes to the parent LiveView. A LiveView that defines other `handle_info/2` clauses and no catch-all raises `FunctionClauseError` and remounts. Which hosts are exposed has not been checked.

**Options.**

1. Keep the gate only on the reads where blocking is right (`schema/2`, `fetch_adaptor`, `ensure_loaded`) and let `catalogue/1`, `packages/1`, `icon/3` and `icon_meta/2` return an immediate `{:error, :not_ready}` the controller can turn into a 503 with `Retry-After`, which the editor already renders as a spinner and Retry button. This gives back the pre-`220f7a4240` HTTP behaviour and keeps the crash fix the gate was built for.
2. Keep the gate everywhere but give the HTTP path a much shorter timeout than the boot path, via a per-call timeout on `gated/2`.
3. Either way, fix the waiter leak on its own: have the scheduler drop a waiter whose call has timed out (it can monitor the caller, or the store can pass a deadline), or have callers use a reference they can discard.

### 7.3 The credential form blocks 90 seconds and then crashes

**Where:** `lib/lightning/credentials.ex:589-596`.

`get_schema/1` raises on any `{:error, _}` from `resolve_name/2` or `schema/2`. It is called from `json_schema_body_component.ex:21` and `credential_form_component.ex:653` with no rescue anywhere upstream, so during a cold or unreachable catalogue the credential form waits the full first-load timeout and then the LiveView process crashes: a 500 on an initial mount, a disconnect-and-remount on a connected socket. The crash was a known limitation before the branch's last day; the gate has made it slow as well as ugly. It also fires for a credential whose adaptor is simply not in the catalogue, cold or not.

Three neighbouring surfaces now disagree about what to do when the catalogue cannot answer:

- `Lightning.Workflows.Job` (`job.ex:157-172`) refuses with "adaptor catalogue is not ready yet, try again shortly".
- `Credential.resolve_schema_name` (`credential.ex:112-126`) silently stores the short name, and the reconciler repairs it later. Settled, see §6.
- `Credentials.get_schema/1` raises.

**Options.** Make `get_schema/1` return an error tuple and have both call sites render a "the adaptor catalogue is still loading" state with a retry. That is the smallest change that removes the crash, and it lines the credential form up with the editor's existing loading/error/Retry pattern. What the user sees and reads in that state is a product question for Brandon's team; the error-tuple change itself is not.

### 7.4 Seeding commands stall for 90 seconds when npm is unreachable

**Where:** `lib/lightning/setup.ex:45-52`.

`_ = Lightning.Adaptors.ensure_loaded()` runs on a cold BEAM with an empty catalogue, so `mix lightning.kickstart` (`kickstart.ex:60`), `Lightning.Setup.setup_user/3` (`setup.ex:23`) and `Lightning.Demo.reset_demo/0` (`demo.ex:16`) each block for the first-load timeout and then proceed as if nothing happened. The return value is discarded and nothing logs the pause.

Concrete case: an airgapped deployer runs `mix lightning.kickstart` before importing a snapshot and waits 90 seconds per invocation with no explanation.

Two consequences to decide on deliberately, not just fix the stall:

- These commands now need outbound npm access to be fast. That is a new coupling between seeding and the network.
- On a box where no instance holds the HighlanderPG lock, the mix task acquires it and runs a full refresh, icon downloads included, as a side effect of seeding.

**Options.** At minimum, log the reason when `ensure_loaded` returns an error so the pause is explained. Better, give the setup path a short timeout of its own (`fetch_adaptor/2` already accepts `opts[:timeout]`, `adaptors.ex:301`; `ensure_loaded/1` would need the same). Or skip the pre-load entirely and accept a lazy lookup inside `fun`. The comment at `setup.ex:47-49` explains why the pre-load is there: to avoid a source fetch inside `fun`'s transaction. Removing it needs that answered, for example by moving the adaptor lookups out of the transaction.

### 7.5 PR #5077 and this branch have to be sequenced

Checked on 10 Sep, re-checked 14 Sep: #5077 is still open and this branch does not contain it. Nothing in the branch history records a decision.

#5077 ("Fix metadata breaking during overlapping or unparseable adaptor installs") fixes two bugs in `AdaptorService`, the on-the-fly npm install that puts packages on the worker pod: a lookup during an in-flight install could see a half-built placeholder whose stored version literal `latest` is not valid semver and raises on comparison; and the editor's metadata channel handler passed `job.adaptor` through unresolved, unlike the worker and AI assistant paths. The fix converts `AdaptorService` from an `Agent` to a `GenServer`, queues overlapping installs, and resolves `latest` in `workflow_channel.ex`. Files: `adaptor_service.ex`, `workflow_channel.ex`, `CHANGELOG.md`, three tests.

`AdaptorService` is the one part of the old world this branch leaves essentially intact, so the rewrite does not supersede #5077 and both bugs are present here. Six branch commits touch `adaptor_service.ex` (`931f16a020`, `220f7a4240`, `2a6499a523`, `4348ac2d15`, `790087de3f`, `69f6595ed2`), and `931f16a020` changed `install/2`'s error handling, the same function #5077 restructures. Whichever lands second gets a conflict in `install/2`.

Also relevant: #4801 targets `release-2.19.0` but the branch is based on `main` and `release-2.19.0` is not an ancestor of `HEAD`. Merging as-is would carry `main`'s commits into the release branch. Rebase onto `release-2.19.0` (which drops the five cherry-picked commits in §12 as duplicates) or retarget the PR; decide together with the #5077 order.

### 7.6 Concurrent schema fetches are not coalesced across nodes

Raised on 11 Sep, never built. `Store.read_schema/2` uses `Cachex.fetch/4`, which coalesces concurrent callers for the same key on one node, so two callers on the same node wanting the same schema do share one fetch. There is no coalescing across nodes and no in-flight registry in the scheduler or `NPM.Schema`. Not a defect; it is the obvious next thing if the cold-start window turns out to be painful in practice.

### 7.7 The CHANGELOG undersells the upgrade

**Where:** `CHANGELOG.md:46-48`, under `## [Unreleased]` → `### Changed`.

One entry: "Lightning now keeps its own adaptor registry instead of fetching the list from npm at startup, so new adaptors and versions show up without a rebuild or redeploy. See ADAPTORS.md. #4801". It says nothing about `SCHEMAS_PATH` and `ADAPTORS_REGISTRY_JSON_PATH` being removed, the nine new `ADAPTORS_*` variables, the `_MS` → `_SECONDS` rename from `f6325ee457`, the deleted `install_schemas` / `install_adaptor_icons` tasks, the three migrations, or the icon volume.

Anyone upgrading from the CHANGELOG alone will not learn they have environment variables to delete. This needs writing before the branch merges.

### 7.8 Smaller known limitations, carried forward

Not blockers, but they belong in whatever goes to Services:

- **Up to an hour of staleness by default.** Workaround: Settings → Maintenance, or `mix lightning.adaptors.refresh`.
- **The icon cache needs a persistent volume.** The official image and compose handle it; any other deployment must mount storage at `ADAPTORS_ICONS_PATH` or icons re-download on every restart. Outside the image the default sits under the system temp directory, which most container platforms wipe.
- **The credential type list degrades silently.** `get_type_options/0` (`credential_form_component.ex:1176-1193`) returns `[]` for the adaptor block on `{:error, _}`, so the "new credential" list collapses to Raw JSON plus whatever OAuth clients exist, with no error shown.
- **Schemas missing upstream stop being retried after an hour.** See §2, "How the scheduler treats a missing schema". Workaround: `mix lightning.adaptors.refresh --name <package>`.
- **`--name` refresh is the blunt instrument.** It bypasses change detection and takes upstream literally, so it will clear a stored schema if upstream now reports none. Intended, but it can remove data a periodic tick would have preserved.
- **Local mode shows version `local`** in the picker for every adaptor (`store.ex:341-342`), though the database holds the real semver.
- **Object-typed credential schema fields render as a code area**, not a structured form (`json_schema_body_component.ex:113`).
- **Hardcoded exclusions.** `@openfn/language-devtools`, `-template`, `-fhir-jembi` and `-collections` are never listed, along with anything npm marks deprecated. Changing the list needs a code change.
- **Multi-node partition.** A node that misses a change broadcast serves stale data until it sees the other node return, then re-warms from Postgres. Scheduler failover on leader death takes a few seconds.

---

## 8. Questions that belong to other teams

- **Release version.** Which Lightning release does this ship in? The PR targets `release-2.19.0` and the CHANGELOG entry sits under Unreleased. Brandon's team owns the answer.
- **Customer impact.** Which hosted or client deployments currently set `SCHEMAS_PATH` or `ADAPTORS_REGISTRY_JSON_PATH`, or use `LOCAL_ADAPTORS` / `OPENFN_ADAPTORS_REPO`? Those env files need editing before upgrade. Not visible from the repo; Aleksa's team for the client picture.
- **Which deployments need persistent storage at `ADAPTORS_ICONS_PATH`?** A per-deployment decision. Nahrek's team for the infrastructure side.
- **Are there airgapped or offline customers today?** If so, someone owns building and distributing snapshot files and a refresh cadence for them. Aleksa's team.
- **Public docs.** Is docs.openfn.org being updated? ADAPTORS.md is in-repo only and is the only written record of the offline procedure. Jack's team.
- **First-run timing on a real production network.** The concurrency limits are clear but the wall-clock time for a cold first refresh against npm from a production region has not been measured. Time it during UAT and record it; it directly informs whether 90 seconds is the right `first_load_timeout`. Whoever runs UAT.

---

## 9. How to check your work

```sh
mix test test/lightning/adaptors                  # 340 tests, the subsystem's own; 0 failures on 14 Sep
mix test                                          # full suite
mix verify                                        # format, credo, dialyzer, sobelow
```

Known flakes unrelated to this work: `FifoRunQueueTest` and `RunsTest` claim-ordering, both clean in isolation.

The subsystem compiles under `warnings_as_errors`, so a warning is a build failure.

### Driving a controlled upstream

Real npm means waiting for real upstream events. For anything needing a controlled upstream (a new version, a new adaptor, an icon change, a registry that is down) use the record-and-replay proxy in `tooling/adaptor_cache/` (README there):

```sh
bin/adaptor_cache up        # prints the three ADAPTORS_NPM_*_URL exports
bin/adaptor_cache logs      # watch cache=HIT / MISS / ERROR per request
bin/adaptor_cache publish @openfn/language-http 9.9.9
bin/adaptor_cache down      # simulate an unreachable registry
```

It also has `status`, `purge`, `check` and `scenario save/restore`. The cache directory defaults to `/tmp/adaptor_cache` (`ADAPTOR_CACHE_DIR`). `publish` deliberately updates both the packument and the search response's `latest_version`. Hand-editing only one is a silent no-op, because change detection diffs the search response against the database.

### Manual refresh paths

```sh
mix lightning.adaptors.refresh                                # full refresh, waits, prints counts
mix lightning.adaptors.refresh --name @openfn/language-http   # one adaptor, ignores change detection
```

Exit codes (`lightning.adaptors.refresh.ex`): full refresh `0` on success, `2` if the cycle succeeded but listed nothing, on timeout, or on any other error; `--name` gives `0` on success, `1` if the adaptor does not exist, `2` on any other error. The task accepts only `--name`; there is no `--strategy` or `--source`.

On a release image: `bin/lightning rpc 'Lightning.Adaptors.refresh(await: true)'` and `bin/lightning rpc 'Lightning.Adaptors.refresh_package("@openfn/language-http")'`.

In the UI: Settings → Maintenance, superuser only (§5).

---

## 10. Scenarios worth running by hand

Condensed from the UAT plan written for Services on 10 Sep, corrected for the 14 Sep changes. Expected values are what the code does today.

1. **Fresh install.** Empty DB, network up, defaults. Start; confirm pages serve immediately; logs show `Adaptors[npm]: catalogue is empty at boot — refreshing now`, then `scheduler started interval=3600000ms next_tick_in=0ms`, then a tick summary with `listed` in the low hundreds and `errors=0`. Picker lists adaptors with icons. `SELECT count(*) FROM adaptors` and `adaptor_versions` non-zero. `GET /adaptors/catalogue` returns 200 with entries carrying `name`, `latest_version`, `versions`, `repository`, `icon_urls`. Files under `$ADAPTORS_ICONS_PATH/npm/<adaptor>/square.<sha8>.png`. Saving a workflow before the first refresh finishes waits up to 90s, then says "The adaptor catalogue is still loading. Try again shortly." That is correct behaviour.
2. **New version upstream.** `bin/adaptor_cache publish @openfn/language-http 9.9.9`, leave an editor open, `mix lightning.adaptors.refresh`. Refresh reports `changed=1 fetched=1`; `9.9.9` appears in the open picker without a reload; `latest_version` in the DB shows `9.9.9`; the catalogue ETag changes.
3. **New adaptor upstream.** `publish @openfn/language-brand-new 1.0.0`, refresh. Appears in the picker with a grey placeholder icon (`icon_urls` null); row count up by one.
4. **Icon change.** Replace the recorded icon bytes under the cache dir, refresh (or Maintenance → Refresh Adaptor Icons). Catalogue gives a new `sha8`; the old URL 302s to the new one with `no-store`; the new URL is 200 with the immutable headers; `icon_square_sha256` changed; summary shows `icons=` or `healed=` non-zero. An icon-only change is picked up even when the version did not bump; that is the `healed` counter.
5. **Schema change.** Edit the recorded `configuration-schema.json`, publish a version bump, refresh, reopen an existing credential of that type. The form shows the new field; the stored body is untouched. `schema_sha256` on the row changed. `SELECT schema FROM credentials` shows full package names (the reconciler). An adaptor with no schema does not appear in the credential type list but does appear in the picker; its `package_meta.has_schema` is false.
6. **Legacy schema names.** On an instance upgraded from a pre-branch version, `SELECT DISTINCT schema FROM credentials` shows short names before and full names after the first refresh. Unresolvable names are left alone. No audit rows.
7. **Registry unreachable.** (A) Populated catalogue, `bin/adaptor_cache down`, refresh: `list_adaptors failed` warning, `errors=1 changed=0`, task exits 2, everything keeps serving, row counts and `updated_at` unchanged; bring it back, clean tick. (B) Empty catalogue, no network: pages serve; save is rejected after up to 90s; `GET /adaptors/catalogue` is 503 after up to 90s; editor shows the load error with Retry. (C) One broken packument: `fetch_adaptor(<name>) failed`, `errors=1`, rest lands. (D) GitHub only down: metadata lands, `fetch_icons failed … persisting records without icons`.
8. **Manual refresh via UI and CLI.** §9. Negative test: a non-superuser at `/settings/maintenance` is redirected to `/projects` with a no-access flash and sees no Maintenance sidebar entry.
9. **Offline install.** §4. Deliberate failure to check: skip the icon tarball and confirm the catalogue populates but icons are missing.
10. **Local mode.** `ADAPTORS_STRATEGY=local`, `ADAPTORS_LOCAL_REPO=/path/to/adaptors`. Only checked-out adaptors appear, all showing version `local` in the picker; `SELECT source, latest_version FROM adaptors` shows `local` as the source and real semvers. Schemas and icons are read live from the checkout, so editing a schema needs only a refresh. Two roots: first wins, the log names shadowed packages. Negative: no path at all fails boot naming both variables.
11. **Deprecated adaptor.** Absent from the picker, the credential type list and `GET /adaptors/catalogue`; present in the table with `deprecated = true`; a job pinned to it still validates, saves and runs.
12. **Deprecated env vars.** `LOCAL_ADAPTORS=true` and `OPENFN_ADAPTORS_REPO` with none of the new variables: works as local mode and logs both deprecation warnings.
13. **Two nodes.** Only one logs refresh ticks; kill it and the other takes over within seconds; the follower sees the leader's changes; both nodes return the same catalogue.
14. **Catalogue caching.** 200 with `etag`, `cache-control: private, no-cache`, `vary: Cookie`; 304 on `If-None-Match`; new etag after a change; 401 `{"error": "Unauthorized"}` without a cookie.

---

## 11. Loose threads

- A `mix release` failure in dev mode ("Could not read configuration file... functions, references, and pids... `LightningWeb.Endpoint`") turned up on 11 Sep while reproducing an unrelated bug. It looks like a pre-existing `config/dev.exs` release-config problem rather than anything to do with adaptors, and it has not been confirmed fixed.
- `test/lightning/adaptor_service_test.exs:1-6` still has a moduledoc describing `AdaptorService.known?/1`, which `931f16a020` deleted. Stale documentation, not a failing test.
- `workflow_channel.ex:109-117` keeps a `request_adaptors` handler with no caller in `assets/js` other than the channel test and a test-helper README. If it is dead, delete it; if it is kept, note that it hides `{:error, _}` as an empty list (`:993-997`), the same shape §7.1 is about.
- `Registry.scoped_package_names/0` has no distinct branch for a 200 whose body is not a map; it falls through to `{:error, {:http_status, 200}}`. Harmless, just a confusing error to read in a log.

## 12. Unrelated work carried on the branch

Ten of the 41 commits are not adaptor work. Five are already on `release-2.19.0` and will drop out as duplicates on a rebase onto it: `f946809b0f` (sandbox merge collections fix, #5054), `ecc0cecca2` and `b0fabc55b9` and `f01b2beb6a` (AI assistant changes, #5161, #5143, #5155), `605a3bb594` (special characters in workflow, step and credential names, #5106). Five are branch-only and unrelated: `34a73347a3` (docs-style rule and skills), `67fce6335b` (locale pin for the JS test run), `dffd89e67b` (GitHubSyncModal test), `4d6b01ed0b` (sobelow 0.15.0), `43ee0c8fe1` (session store teardown in tests). None of them is part of this story; the first five have their own CHANGELOG entries.
