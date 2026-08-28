# Adaptor Cache

> A local caching reverse proxy sitting in front of the three upstreams
> `Lightning.Adaptors.*` reads from.

Every `Lightning.Adaptors.Scheduler` refresh tick makes one npm `/-/v1/search`
call, then one packument call and one jsDelivr schema call per changed package,
plus up to four `raw.githubusercontent.com` calls per package for icons (two
shapes x the png-then-svg fallback). Iterating on the subsystem means running
that loop over and over against the real internet. This proxy caches all of it
to disk so the second and every later run is local, and the whole thing works
offline (on a plane, on bad wifi, wherever).

Driven by `bin/adaptor_cache` from the repo root; see that script's `--help` for
the full command list.

## What's in this folder

| File                 | Purpose                                                                                      |
| -------------------- | -------------------------------------------------------------------------------------------- |
| `docker-compose.yml` | Runs the `nginx` container, bound to `127.0.0.1` only                                        |
| `nginx.conf`         | The three `/npm/`, `/jsdelivr/`, `/github/` proxy locations and the persistent on-disk cache |

## Prerequisites

- Docker + Docker Compose
- **Bring the cache up at least once while online.** nginx resolves
  `registry.npmjs.org`, `cdn.jsdelivr.net` and `raw.githubusercontent.com` at
  container startup, not per-request. Starting it offline for the first time
  fails with `host not found in upstream` — do the first `bin/adaptor_cache up`
  with a real connection, after that it's fine offline.

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

## Usage

```sh
bin/adaptor_cache up        # start the proxy and print the export lines
bin/adaptor_cache down      # stop the proxy, keeping the cache on disk
bin/adaptor_cache status    # show container state and reachability
bin/adaptor_cache purge     # stop the proxy AND drop the cache volume
bin/adaptor_cache logs      # tail the access log (cache=HIT / cache=MISS)
bin/adaptor_cache check     # probe all three prefixes, prove MISS then HIT
bin/adaptor_cache --help    # full usage
```

With the cache up and the three vars exported, run
`mix lightning.refresh_adaptors` as usual. The first run populates the cache;
every run after that should be fast and work with no network at all.

### Reading `bin/adaptor_cache logs`

Each line is one proxied request:

```
2026-08-25T10:00:00+00:00 status=200 cache=HIT GET /npm/-/v1/search?text=@openfn&size=250
```

- `cache=HIT` — served entirely from disk, no upstream request made.
- `cache=MISS` — not in the cache (or expired), fetched from the real upstream
  and stored.
- `cache=EXPIRED` / `cache=REVALIDATED` — the entry had aged out, so nginx did
  go upstream. REVALIDATED means it sent a conditional request, got a 304, and
  reused what was on disk.
- `cache=STALE` / `cache=UPDATING` — nginx served what it had on disk because
  the upstream was unreachable, or because another request was already
  refetching. This is what you see offline.

On a warm cache, MISS should only appear for packages the cache has never seen.

## How the URL mapping works

The proxy has one location block per upstream, and Lightning's `NPM` strategy
already builds full paths under each — the proxy just rewrites the host:

| Lightning request                      | Through the proxy                                                                          | Prefix       | Real upstream                           |
| -------------------------------------- | ------------------------------------------------------------------------------------------ | ------------ | --------------------------------------- |
| npm search / packument (`registry.ex`) | `http://localhost:4874/npm/-/v1/search?...`                                                | `/npm/`      | `https://registry.npmjs.org/...`        |
| jsDelivr schema fetch (`schema.ex`)    | `http://localhost:4874/jsdelivr/npm/@openfn/language-http@2.1.0/configuration-schema.json` | `/jsdelivr/` | `https://cdn.jsdelivr.net/...`          |
| GitHub icon fetch (`github.ex`)        | `http://localhost:4874/github/OpenFn/adaptors/main/packages/http/assets/square.png`        | `/github/`   | `https://raw.githubusercontent.com/...` |

Setting `ADAPTORS_NPM_REGISTRY_URL`, `ADAPTORS_NPM_JSDELIVR_URL` and
`ADAPTORS_NPM_GITHUB_URL` to the proxy's `/npm`, `/jsdelivr` and `/github` base
URLs is all that's needed — the strategy code appends the same paths it always
did, just against a different host.

## Caveats

- **The legacy `Lightning.AdaptorRegistry` and `mix lightning.install_schemas`
  bypass this entirely.** Both have hardcoded upstream URLs and don't read the
  `ADAPTORS_NPM_*` env vars, so they'll always hit the real internet regardless
  of whether the cache is up.
- **Redirects bypass the cache.** Tesla's `FollowRedirects` middleware requests
  the absolute `Location` URL, which points at the real upstream even when the
  redirect is same-host, so anything that 30x's is fetched live.
- **Never set this as your global npm registry in `~/.npmrc`.** The `/npm/`
  prefix is a transparent GET proxy of registry.npmjs.org, so npm would mostly
  work, badly: this cache ignores Cache-Control and holds 200s for seven days,
  so `npm install` resolves against a week-stale packument, and npm records the
  registry it fetched from in `package-lock.json`'s `resolved` URLs, giving you
  a lockfile that only installs on a machine running this container.

## Troubleshooting

**`host not found in upstream` on startup.** You brought the container up
offline for the first time. Get online and run `bin/adaptor_cache up` once so
nginx can resolve the three upstream hostnames, then it's fine offline after
that.

**`bin/adaptor_cache check` fails on one prefix.** Run `bin/adaptor_cache logs`
and look for the failing request — a `cache=MISS` on the _second_ identical
request usually means the upstream is refusing the request outright (check
status code) rather than a caching problem.

**Port already in use.** Set `ADAPTOR_CACHE_PORT` to something else before
`bin/adaptor_cache up`, and update the three `ADAPTORS_NPM_*_URL` exports to
match the new port.

**Stale or wrong data cached.** `bin/adaptor_cache purge` drops the on-disk
cache volume entirely (unlike `down`, which keeps it); `up` again to rebuild
from empty.
