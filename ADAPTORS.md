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

`ADAPTORS_ICONS_PATH` defaults to `lightning/adaptor_icons` under the temp
directory. On a release image (no Mix), dump with:

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

An imported catalogue survives the hourly refresh; a failed one logs a warning
and leaves rows alone.

The worker installs adaptor packages into `ADAPTORS_PATH` itself, a separate
download not covered here.

## Keeping the catalogue fresh

Lightning refreshes the catalogue hourly; force one, on a source checkout:

```sh
mix lightning.adaptors.refresh
mix lightning.adaptors.refresh --name @openfn/language-http
```

Without `--name` it runs a full refresh and waits; with `--name` it refetches
that adaptor regardless of version change. Exit codes are in
`mix help lightning.adaptors.refresh`.

A release image has no Mix; run the same call against the node:

```sh
bin/lightning rpc 'Lightning.Adaptors.refresh(await: true)'
bin/lightning rpc 'Lightning.Adaptors.refresh_package("@openfn/language-http")'
```

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
