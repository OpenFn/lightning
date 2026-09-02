# Adaptor Cache

> A local record-and-replay reverse proxy sitting in front of the three
> upstreams `Lightning.Adaptors.*` reads from.

Every `Lightning.Adaptors.Scheduler` refresh tick makes one npm `/-/v1/search`
call, then one packument call and one jsDelivr schema call per changed package,
plus up to four `raw.githubusercontent.com` calls per package for icons (two
shapes x the png-then-svg fallback). Iterating on the subsystem means running
that loop over and over against the real internet. This proxy records all of it
to disk so the second and every later run is local, and the whole thing works
offline (on a plane, on bad wifi, wherever).

Driven by `bin/adaptor_cache` from the repo root; see that script's `--help` for
the full command list. It's a self-contained script (`Mix.install` pulls in
Bandit + Req the first time it runs).

## What's in this folder

| File/dir     | Purpose                                                       |
| ------------ | ------------------------------------------------------------- |
| `lib/`       | The proxy, `publish`, and `scenario` implementation           |
| `scenarios/` | Saved `scenario save` snapshots (untracked, see `.gitignore`) |

## Recorded responses have no TTL

A recorded response is authoritative until you `purge` it — there is no expiry.
That's deliberate: the recorded files double as hand-editable fixtures, so the
cache is both the everyday dev cache and the mechanism for driving the `publish`
scenarios below, by editing exactly the files it already wrote.

## Environment variables

Point Lightning at the cache by exporting these:

```sh
export ADAPTORS_NPM_REGISTRY_URL=http://localhost:4874/npm
export ADAPTORS_NPM_JSDELIVR_URL=http://localhost:4874/jsdelivr
export ADAPTORS_NPM_GITHUB_URL=http://localhost:4874/github
```

`bin/adaptor_cache up` prints these for you with the right port baked in, so you
don't have to remember them.

- `ADAPTOR_CACHE_PORT` — host port to bind (default: `4874`). Set it before any
  `bin/adaptor_cache` command if `4874` is taken, and update the three exports
  above to match.
- `ADAPTOR_CACHE_DIR` — where recorded responses live (default:
  `/tmp/adaptor_cache`). Several distros age-clean `/tmp` (systemd-tmpfiles: 10
  days on Fedora/Arch) — if a fixture goes missing for no obvious reason, that's
  likely it. Set this to somewhere outside `/tmp` if you want the cache to
  survive indefinitely.

## Usage

```sh
bin/adaptor_cache up                        # start the proxy and print the export lines
bin/adaptor_cache down                      # stop the proxy, keeping the cache on disk
bin/adaptor_cache status                    # show whether it's running and reachable
bin/adaptor_cache purge                     # clear all recorded responses
bin/adaptor_cache logs                      # tail the access log (cache=HIT / cache=MISS)
bin/adaptor_cache check                     # probe all three prefixes, prove MISS then HIT
bin/adaptor_cache publish <name> <version>  # record a synthetic adaptor/version
bin/adaptor_cache scenario save <name>      # snapshot the live cache under that name
bin/adaptor_cache scenario restore <name>   # replace the live cache with that snapshot
bin/adaptor_cache --help                    # full usage
```

With the cache up and the three vars exported, run
`mix lightning.adaptors.refresh` as usual. The first run records the cache;
every run after that is local, with no network needed at all.

### Reading `bin/adaptor_cache logs`

Each line is one proxied request:

```
2026-08-31T10:00:00Z status=200 cache=HIT GET /npm/-/v1/search?text=%40openfn&size=250
```

- `cache=HIT` — served entirely from disk, no upstream request made.
- `cache=MISS` — not recorded yet, fetched from the real upstream and saved.
- `cache=ERROR` — the live fetch itself failed (offline, upstream down); nothing
  is recorded, so the next attempt tries live again.

On a warm cache, MISS should only appear for packages the cache has never seen.

## How the URL mapping works

Lightning's `NPM` strategy already builds full paths under each of the three
base URLs — the proxy fetches the same path from the real upstream and caches it
under the _original_ request path, following any redirect itself first, so the
cached entry reflects the final resolved resource, not an intermediate redirect:

| Lightning request                      | Through the proxy                                                                          | Prefix       | Real upstream                           |
| -------------------------------------- | ------------------------------------------------------------------------------------------ | ------------ | --------------------------------------- |
| npm search / packument (`registry.ex`) | `http://localhost:4874/npm/-/v1/search?...`                                                | `/npm/`      | `https://registry.npmjs.org/...`        |
| jsDelivr schema fetch (`schema.ex`)    | `http://localhost:4874/jsdelivr/npm/@openfn/language-http@2.1.0/configuration-schema.json` | `/jsdelivr/` | `https://cdn.jsdelivr.net/...`          |
| GitHub icon fetch (`github.ex`)        | `http://localhost:4874/github/OpenFn/adaptors/main/packages/http/assets/square.png`        | `/github/`   | `https://raw.githubusercontent.com/...` |

## Recorded files as fixtures

A recorded response is two files: the raw body, plus a `.meta` sidecar with its
status and content type. The path mirrors the request, so — for example — the
`@openfn/language-http` packument lands at
`/tmp/adaptor_cache/npm/@openfn/language-http`, and the search response (the one
query Lightning ever sends) lands at
`/tmp/adaptor_cache/npm/-/v1/search?text=%40openfn&size=250`. Both are plain
JSON — open and edit them directly to hand-craft a scenario.

## Driving both `publish` scenarios

```sh
bin/adaptor_cache publish @openfn/language-brand-new 1.0.0   # new adaptor appears
bin/adaptor_cache publish @openfn/language-http 9.9.9         # new version of an existing adaptor
```

Either form updates the packument _and_ the search response's `latest_version`
together in one call — `scheduler.ex`'s change-detection compares the search
response against the DB to decide whether to bother fetching the packument at
all, so updating only one is a silent no-op. Run
`mix lightning.adaptors.refresh` (or reopen the picker) afterwards to see it
take effect.

## Scenarios

```sh
bin/adaptor_cache scenario save drill-1      # snapshot the live cache
bin/adaptor_cache purge                      # ...break/change things...
bin/adaptor_cache scenario restore drill-1   # back to exactly that state
```

Scenarios live under `tooling/adaptor_cache/scenarios/<name>/` and stay
untracked (not checked into git) for now.

## Caveats

- **The legacy `Lightning.AdaptorRegistry` and `mix lightning.install_schemas`
  bypass this entirely.** Both have hardcoded upstream URLs and don't read the
  `ADAPTORS_NPM_*` env vars, so they'll always hit the real internet regardless
  of whether the cache is up.
- **Never set this as your global npm registry in `~/.npmrc`.** The `/npm/`
  prefix is a transparent GET proxy of registry.npmjs.org, so npm would mostly
  work, badly: this cache never expires what it records, so `npm install` could
  resolve against an arbitrarily stale packument, and npm records the registry
  it fetched from in `package-lock.json`'s `resolved` URLs, giving you a
  lockfile that only installs on a machine running this proxy.

## Troubleshooting

**`bin/adaptor_cache check` fails on one prefix.** Run `bin/adaptor_cache logs`
and look for the failing request — a `cache=MISS` on the _second_ identical
request usually means the upstream is refusing the request outright (check
status code) rather than a caching problem.

**Port already in use.** Set `ADAPTOR_CACHE_PORT` to something else before
`bin/adaptor_cache up`, and update the three `ADAPTORS_NPM_*_URL` exports to
match the new port.

**Stale or wrong data cached.** `bin/adaptor_cache purge` drops every recorded
response; `up` keeps running and the next request re-fetches live.
