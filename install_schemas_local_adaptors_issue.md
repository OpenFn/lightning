# `mix lightning.install_schemas` ignores `LOCAL_ADAPTORS`

## Summary

`mix lightning.install_schemas` always fetches credential schemas from the
network (npm + jsdelivr) and has no awareness of `LOCAL_ADAPTORS` /
`OPENFN_ADAPTORS_REPO`. When running against local adaptors, no credential
schemas are installed for those adaptors, so their credential types are missing
from the UI and editing an affected credential hard-crashes the LiveView.

## Current behaviour

`lib/mix/tasks/install_schemas.ex` unconditionally:

- enumerates published `@openfn/language-*` packages from `registry.npmjs.org`
  (`fetch_schemas/2`, line 141)
- fetches each `configuration-schema.json` from `cdn.jsdelivr.net` (line 103)
- writes to `schemas_path` as `<name>.json` (strips `@openfn/language-`,
  `write_schema/3`, line 84)

The only env it reads is `:schemas_path`. There is no reference to
`LOCAL_ADAPTORS` or `OPENFN_ADAPTORS_REPO`.

## Expected behaviour

`LOCAL_ADAPTORS=true mix lightning.install_schemas` should populate
`priv/schemas/` from the local adaptor monorepo(s) in `OPENFN_ADAPTORS_REPO`
instead of hitting the network — matching how the adaptor registry already
resolves local adaptors.

## Downstream impact

The credential UI is driven entirely by files in `priv/schemas/`
(`get_type_options/1` in `credential_form_component.ex:1164` globs the dir).
With local adaptors, the schema file never exists, so:

- the adaptor's credential type is absent from the "new credential" picker
- editing an existing credential whose `schema` names that adaptor raises in
  `get_schema/1` (`credentials.ex:585`) — `File.read` returns
  `{:error, :enoent}` and the whole credential-form LiveView crashes:

```
** (RuntimeError) Error reading credential schema. Got: :enoent
    lib/lightning/credentials.ex:586: Lightning.Credentials.get_schema/1
    lib/lightning_web/live/credential_live/json_schema_body_component.ex:21: ...
```

## Proposed implementation

The naming already aligns: local packages live at `<repo>/packages/<name>/` and
map to `@openfn/language-<name>` (`adaptors_in_repo/1` in
`adaptor_registry.ex:293`), which is exactly the `<name>.json` convention
`install_schemas` uses.

When `Lightning.AdaptorRegistry.local_adaptors_enabled?/0` (i.e.
`local_adaptors_repos != []`):

- enumerate packages from the configured repos instead of npm
- copy each package's local `configuration-schema.json` into `schemas_path`
  (skip packages that don't ship one), reusing existing dir listing/dedupe logic
  where possible
- keep the network path as the default when `LOCAL_ADAPTORS` is off

## Secondary hardening (optional, separate concern)

Regardless of source, `get_schema/1` (`credentials.ex:585`) should not crash the
form on a missing file. It should degrade (e.g. fall back to a raw-JSON body
editor + inline "schema unavailable" notice) and log the offending `schema_name`
— the current `raise` omits it.

## Acceptance criteria

- [ ] `LOCAL_ADAPTORS=true mix lightning.install_schemas` writes schemas from
      `OPENFN_ADAPTORS_REPO`, no network calls
- [ ] Local-only adaptors appear in the credential type picker and their forms
      render
- [ ] Default (network) behaviour unchanged when `LOCAL_ADAPTORS` is unset/false
