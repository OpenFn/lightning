# Adaptors

The adaptor registry is the catalogue of adaptors, versions, credential schemas
and icons that the workflow editor shows. Lightning fetches it from npm by
default and keeps a copy in Postgres. For the Elixir side, start at
`Lightning.Adaptors`.

## Using local adaptors

Point Lightning at a checkout of the adaptors monorepo instead of npm:

```sh
ADAPTORS_STRATEGY=local
ADAPTORS_LOCAL_REPO=/path/to/adaptors
```

The path is the repository root, not its `packages/` directory. Every
subdirectory of `packages/` with a `package.json` becomes an adaptor, named and
versioned from that file. Lightning also reads `configuration-schema.json` for
the credential form, and `assets/square` and `assets/rectangle` as `.png` or
`.svg` for the icons. A package without them still appears, with no credential
form or icon.

To layer a private checkout over the public one, give more than one root, comma
separated:

```sh
ADAPTORS_LOCAL_REPO=/path/to/private-adaptors,/path/to/adaptors
```

A package found in more than one root comes from the first root only. Lightning
logs a warning naming each shadowed package on every catalogue scan, not just at
boot.

> #### Note {: .info}
>
> Lightning still accepts the old names for these two settings,
> `LOCAL_ADAPTORS=true` and `OPENFN_ADAPTORS_REPO`. Each warns at boot only when
> Lightning falls back to it: `LOCAL_ADAPTORS=true` when `ADAPTORS_STRATEGY` is
> unset, `OPENFN_ADAPTORS_REPO` when the strategy is local and
> `ADAPTORS_LOCAL_REPO` is not set.

## Running without internet access

Copy the catalogue from an instance that has internet access and has finished a
refresh. On that instance, dump the catalogue and archive the icons directory.
The dump holds the icon metadata only, so the icon files have to travel with it:

```sh
mix lightning.adaptors.dump --path snapshot.json
tar czf icons.tar.gz -C "$ADAPTORS_ICONS_PATH" .
```

If `ADAPTORS_ICONS_PATH` is not set, the directory is `lightning/adaptor_icons`
under the system temp directory. On a release image, which has no Mix, dump
with:

```sh
bin/lightning eval 'Lightning.Release.dump_adaptors("/path/to/snapshot.json")'
```

On the offline instance, unpack the icons where `ADAPTORS_ICONS_PATH` points,
then import the snapshot:

```sh
mkdir -p "$ADAPTORS_ICONS_PATH"
tar xzf icons.tar.gz -C "$ADAPTORS_ICONS_PATH"
mix lightning.adaptors.import --path snapshot.json --replace
```

On a release image, import with:

```sh
bin/lightning eval 'Lightning.Release.seed_adaptors("/path/to/snapshot.json", replace: true)'
```

With no populated instance to dump from, build the snapshot straight from npm on
any machine with internet access. This needs no database and carries no icons:

```sh
mix lightning.adaptors.snapshot --path snapshot.json
```

Import it as above.

If you run internal mirrors instead, any npm-compatible registry works. Set
`ADAPTORS_NPM_REGISTRY_URL`, `ADAPTORS_NPM_JSDELIVR_URL` and
`ADAPTORS_NPM_GITHUB_URL`, and leave the strategy as npm. Set
`ADAPTORS_NPM_GITHUB_REF` too if the mirror serves a branch other than `main`.

An imported catalogue survives the hourly refresh. When the refresh cannot reach
its source it logs a warning and leaves the existing rows alone.

The worker installs adaptor packages into `ADAPTORS_PATH` on its own. That is a
separate download and none of the above provides it.

## Keeping the catalogue fresh

Lightning refreshes the catalogue from its source every hour. To force a refresh
now, on a source checkout:

```sh
mix lightning.adaptors.refresh
mix lightning.adaptors.refresh --name @openfn/language-http
```

Without `--name` it runs a full refresh and waits for it to finish. With
`--name` it refetches that one adaptor, whether or not its version changed. Exit
codes are in the task's `mix help` output.

A release image has no Mix. Run the same call against the running node instead:

```sh
bin/lightning rpc 'Lightning.Adaptors.refresh(await: true)'
bin/lightning rpc 'Lightning.Adaptors.refresh_package("@openfn/language-http")'
```

## Troubleshooting

- An adaptor is missing from the picker: look for a `fetch_adaptor` warning
  naming it in the log, then force a refresh with `--name`.
- A new version is not showing: the hourly refresh has not run yet. Force one,
  or wait for the next.
- Icons are missing after an import: the icons directory never reached
  `ADAPTORS_ICONS_PATH` on this instance, or the dump came from a Lightning
  version that did not write icon metadata. Redo the dump and copy the
  directory.
- A local package is ignored: an earlier root in `ADAPTORS_LOCAL_REPO` has a
  package with the same name. The log names each shadowed package.
- A boot warning says a variable is deprecated: rename `LOCAL_ADAPTORS=true` to
  `ADAPTORS_STRATEGY=local` and `OPENFN_ADAPTORS_REPO` to `ADAPTORS_LOCAL_REPO`.
