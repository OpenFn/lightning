# Adaptors

The adaptor registry catalogues adaptors, versions, credential schemas and icons
for the workflow editor. Lightning fetches it from npm by default, cached in
Postgres. For the Elixir side, start at `Lightning.Adaptors`.

## Using local adaptors

Point Lightning at a checkout of the adaptors monorepo, not npm:

```sh
ADAPTORS_STRATEGY=local
ADAPTORS_LOCAL_REPO=/path/to/adaptors
```

The path is the repo root, not `packages/`. Each subdirectory with a
`package.json` becomes an adaptor, named and versioned from it. Lightning also
reads `configuration-schema.json` for the credential form and
`assets/square`/`assets/rectangle` (`.png`/`.svg`) for icons; a package without
them still appears, minus the form or icon.

To layer a private checkout over the public one, comma-separate multiple roots:

```sh
ADAPTORS_LOCAL_REPO=/path/to/private-adaptors,/path/to/adaptors
```

A package in multiple roots comes from the first; Lightning logs each shadowed
package on every scan, not just at boot.

> #### Note {: .info}
>
> Lightning still accepts the old names `LOCAL_ADAPTORS=true` and
> `OPENFN_ADAPTORS_REPO`, warning at boot only when it falls back to them:
> `LOCAL_ADAPTORS=true` when `ADAPTORS_STRATEGY` is unset,
> `OPENFN_ADAPTORS_REPO` when the strategy is local and `ADAPTORS_LOCAL_REPO` is
> unset.

## Running without internet access

On an internet-connected, refreshed instance, dump the catalogue. The dump holds
icon metadata only, so archive the icons directory too:

```sh
mix lightning.adaptors.dump --path snapshot.json
tar czf icons.tar.gz -C "$ADAPTORS_ICONS_PATH" .
```

`ADAPTORS_ICONS_PATH` is `/app/priv/adaptor_icons` in the official image, and
otherwise defaults to `lightning/adaptor_icons` under the temp directory. On a
release image (no Mix), dump with:

```sh
bin/lightning eval 'Lightning.Release.dump_adaptors("/path/to/snapshot.json")'
```

Offline, unpack icons to `ADAPTORS_ICONS_PATH`, then import:

```sh
mkdir -p "$ADAPTORS_ICONS_PATH"
tar xzf icons.tar.gz -C "$ADAPTORS_ICONS_PATH"
mix lightning.adaptors.import --path snapshot.json --replace
```

On a release image, import with:

```sh
bin/lightning eval 'Lightning.Release.seed_adaptors("/path/to/snapshot.json", replace: true)'
```

With no populated instance, build the snapshot from npm anywhere online (no
database, no icons):

```sh
mix lightning.adaptors.snapshot --path snapshot.json
```

Import as above.

Internal mirrors: any npm-compatible registry works. Set
`ADAPTORS_NPM_REGISTRY_URL`, `ADAPTORS_NPM_JSDELIVR_URL` and
`ADAPTORS_NPM_GITHUB_URL`, leave the strategy as npm, and set
`ADAPTORS_NPM_GITHUB_REF` if the mirror serves a branch other than `main`.

A registry that answers but lists no `@openfn/language-*` packages is treated as
a failed listing, not as a catalogue with nothing in it. That is nearly always a
mistyped mirror URL or a mirror that has not synced the `@openfn` scope. The
rows already in Postgres stay as they are and the next refresh tries again. A
local checkout with no packages in it is genuinely empty, and is read as such.

An imported catalogue survives the hourly refresh; a failed one logs a warning
and leaves rows alone.

The worker installs adaptor packages into `ADAPTORS_PATH` itself, a separate
download not covered here.

## Keeping the catalogue fresh

Lightning refreshes the catalogue hourly. Set
`ADAPTORS_REFRESH_INTERVAL_SECONDS` to change that interval, or to `0` to
disable scheduled refreshes. Force one manually, on a source checkout:

```sh
mix lightning.adaptors.refresh
mix lightning.adaptors.refresh --name @openfn/language-http
```

Without `--name` it runs a full refresh and waits; with `--name` it refetches
that adaptor regardless of version change. A cycle that ran but wrote no rows
exits `0`, since an empty result from a readable source is not a failure; a
source that could not be listed at all exits `2`. The full list is in
`mix help lightning.adaptors.refresh`.

A release image has no Mix; run the same call against the node:

```sh
bin/lightning rpc 'Lightning.Adaptors.refresh(await: true)'
bin/lightning rpc 'Lightning.Adaptors.refresh_package("@openfn/language-http")'
```

## While the catalogue is still loading

A fresh instance has an empty catalogue until the first refresh lands. Reads do
not wait for it. The adaptor picker and the credential form show "Couldn't load
adaptors" with a Retry button, and `GET /adaptors/catalogue` replies 503 with a
`retry-after` header. An open editor picks the catalogue up on its own once the
load lands, without a page reload; the credential form recovers when you press
Retry, and the endpoint answers normally on the next request.

Saving a workflow is the exception. It has to check the job's adaptor against
the catalogue before it can store it, so it waits for the first load, up to 90
seconds, and rejects the save with "adaptor catalogue is not ready yet" if
nothing has arrived by then.

So an instance that cannot reach npm at all comes up, serves every page and
retries in the background, but cannot save a workflow until the catalogue has
loaded once. Import a snapshot to give it one.

## Troubleshooting

- Adaptor missing from the picker: find its `fetch_adaptor` warning in the log,
  then force a refresh with `--name`.
- New version not showing: the hourly refresh hasn't run. Force one, or wait.
- Icons missing after import: they never reached `ADAPTORS_ICONS_PATH` on this
  instance, or the dump predates icon metadata. Redo the dump and copy the
  directory.
- Local package ignored: an earlier `ADAPTORS_LOCAL_REPO` root has a package of
  the same name; the log names each shadowed package.
- Deprecated-variable boot warning: rename `LOCAL_ADAPTORS=true` to
  `ADAPTORS_STRATEGY=local` and `OPENFN_ADAPTORS_REPO` to `ADAPTORS_LOCAL_REPO`.
- Picker stuck on "Couldn't load adaptors", or the catalogue endpoint answering
  503: the first load has not finished. See
  [While the catalogue is still loading](#while-the-catalogue-is-still-loading).
- Workflow save rejected with "adaptor catalogue is not ready yet": the same
  thing, ninety seconds in. If the instance cannot reach npm, import a snapshot;
  see [Running without internet access](#running-without-internet-access).
- Refresh exiting `2` with `:empty_listing`: the registry answered but served no
  `@openfn` packages. Check `ADAPTORS_NPM_REGISTRY_URL`.
