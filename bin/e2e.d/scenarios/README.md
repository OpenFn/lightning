# Kickstart scenarios

A scenario is a YAML (or JSON) file describing the exact state you want a
Lightning instance booted into: users, credentials, projects, workflows.
Scenarios are executed by `Lightning.Kickstart`, which provisions workflows
through the same engine as the `/api/provision` HTTP API.

## Running

```bash
# via the e2e manager (uses a per-scenario DB snapshot for fast resets)
bin/e2e start --scenario example          # scenarios/example.yaml
bin/e2e setup --scenario /path/to/my.yaml
bin/e2e reset --scenario example

# directly, against whatever DATABASE_URL/MIX_ENV is configured
mix lightning.kickstart bin/e2e.d/scenarios/example.yaml \
  --manifest /tmp/manifest.json
```

Re-running a scenario is **idempotent**: users are matched by email, credentials
by owner+name, and projects/workflows/jobs/triggers/edges get deterministic ids
derived from their names, so everything upserts instead of duplicating.

Two things a re-run does not do. It never removes records, and the provisioner
treats the document as the complete set, so a project holding a workflow or
collection the scenario doesn't declare fails with a message naming it - add it
to the scenario, or reset the project. And renaming a workflow or collection
fails for the same reason; pin an explicit `id:` on a workflow you plan to
rename and its jobs, triggers and edges keep their ids too. Renaming a job,
trigger or edge deletes the old row and creates a new one, which for a webhook
trigger means a new `/i/<id>` URL.

## Manifest

`--manifest PATH` (or `manifest: path` on the Elixir APIs) writes a JSON file
with everything a script or test harness needs to drive the instance: user
emails and API tokens, project/workflow/job/trigger ids, and webhook paths for
webhook triggers (`/i/<trigger-id>`). It holds live API tokens, so it is written
`0600`. For a user who already has an API token, `api_token: true` reuses that
token rather than minting a new one, so pointing a scenario at a real user's
email puts their existing token in the file.

## File format

Top-level keys: `users`, `credentials`, `projects`. All lists optional.

Every key at every level is checked: the scenario's own keys against an
allow-list, and each workflow against the published workflow-spec JSON Schema
(see below). A typo'd or unsupported key raises immediately, naming the bad key,
rather than being silently ignored.

### users

| key          | required | default            | notes                                          |
| ------------ | -------- | ------------------ | ---------------------------------------------- |
| `email`      | yes      |                    | matched on re-run                              |
| `first_name` |          | derived from email |                                                |
| `last_name`  |          | `User`             |                                                |
| `password`   |          | `welcome12345`     |                                                |
| `superuser`  |          | `false`            | boolean, see below                             |
| `api_token`  |          | `false`            | boolean; `true` = generate/reuse, see manifest |

Users are created confirmed. `superuser` and `api_token` accept a real YAML
boolean or the strings `"true"`/`"yes"`/`"false"`/`"no"`; anything else (e.g.
YAML 1.1's `on`/`off`, which `yaml_elixir` doesn't coerce) raises rather than
silently being treated as `false`.

### credentials

| key      | required | default | notes                                  |
| -------- | -------- | ------- | -------------------------------------- |
| `name`   | yes      |         | unique per scenario; matched on re-run |
| `owner`  | yes      |         | email of a user declared above         |
| `schema` |          | `raw`   | e.g. `dhis2`, `http`, `postgresql`     |
| `body`   |          | `{}`    | secret values; supports `${env:VAR}`   |

Existing credentials (matched by owner+name) are reused as-is; bodies are not
updated on re-run.

### projects

| key           | required | notes                                |
| ------------- | -------- | ------------------------------------ |
| `name`        | yes      | url-safe (lowercase, digits, dashes) |
| `description` |          |                                      |
| `members`     | yes      | exactly one `role: owner`            |
| `credentials` |          | names to expose to this project      |
| `collections` |          | list of `{ name }`                   |
| `workflows`   |          |                                      |

`channels` isn't supported yet — declaring it raises rather than being silently
dropped.

Members: `{ email, role }` with role one of `owner`, `admin`, `editor`, `viewer`
(default `editor`). Exactly one member must be `owner`. Re-runs add missing
members and correct drifted roles, but never remove anyone — so an ownership
handover (declaring a different member as `owner`) only succeeds if the old
owner is also declared, with a non-owner role, in the same run; otherwise it
fails cleanly rather than silently leaving two owners.

### workflows

Each entry under a project's `workflows` is a **workflow spec** — the same
hand-writable format the collaborative editor imports and exports (and that
workflow templates are written in), validated against the same JSON Schema
(`assets/js/yaml/schema/workflow-spec.json`) and converted to a provisioning
document by `Lightning.Workflows.Spec`. There's no kickstart-specific workflow
dialect: anything the editor's YAML import accepts works here, and a workflow
exported from the editor can be pasted straight in.

Jobs, triggers and edges are **maps keyed by slug**, and reference each other by
those keys:

```yaml
workflows:
  - name: My Workflow # kickstart requires a name (it derives ids from it)
    jobs:
      transform-data:
        name: Transform data # required
        adaptor: '@openfn/language-common@latest' # required
        body: fn(state => state); # required
        credential: my-credential # optional, see below
    triggers:
      webhook:
        type: webhook # webhook | cron | kafka — required
        enabled: true # required
        webhook_reply: after_completion # optional
    edges:
      webhook->transform-data:
        source_trigger: webhook # a trigger key
        target_job: transform-data # a job key — required
        condition_type: always # required
        enabled: true # required
      transform-data->other-job:
        source_job: transform-data # a job key
        target_job: other-job
        condition_type: js_expression
        condition_expression: state.data.ok
        condition_label: only when ok
        enabled: true
```

`jobs`, `triggers` and `edges` must all be present (use `{}` for none — e.g.
`triggers: {}` for a trigger-less workflow). A cron trigger requires
`cron_expression`, and may name a `cron_cursor_job` (a job key).

Two kickstart-specific notes:

- A job's `credential` names a credential declared at the scenario's top level;
  kickstart resolves it to the job's `project_credential_id`. It's part of the
  published schema, but the editor ignores it.
- `pos` (node positions) is accepted by the schema but not applied — the
  provisioning API has no way to set positions.

Unknown or mistyped keys are rejected by the schema, and unknown provisioner
fields by the provisioner's own validation, so typos fail loudly rather than
being silently dropped.

### Environment interpolation

Any string value anywhere in the file may reference `${env:SOME_VAR}`; the
variable is resolved when the scenario runs and it is an error for it to be
unset. Use this to keep secrets out of committed scenario files.

Interpolation is explicit — only the `${env:...}` form is replaced. Plain
`${...}` is left alone, so JS template literals in job bodies (`${id}`,
`${HOME}`, `${state.data}`) can never collide with it.

## Safety

Kickstarting is a **dev/test facility** — `Lightning.Kickstart.run/1` raises in
any other environment, and mix tasks aren't shipped in a release, so there is no
way to reach it in production.

That's deliberate: a scenario is the desired state for the records it declares,
so re-applying one overwrites them — a job body edited in the editor is
reverted, a disabled trigger is re-enabled. Fine for a database that exists to
be thrown away; wrong for one anybody relies on. To deploy state to a live
instance, use `/api/provision` or the CLI.
