# Bootstrap scenarios

A scenario is a YAML (or JSON) file describing the exact state you want a
Lightning instance booted into: users, credentials, projects, workflows.
Scenarios are executed by `Lightning.Bootstrap`, which provisions workflows
through the same engine as the `/api/provision` HTTP API.

## Running

```bash
# via the e2e manager (uses a per-scenario DB snapshot for fast resets)
bin/e2e start --scenario example          # scenarios/example.yaml
bin/e2e setup --scenario /path/to/my.yaml
bin/e2e reset --scenario example

# directly, against whatever DATABASE_URL/MIX_ENV is configured
mix lightning.bootstrap bin/e2e.d/scenarios/example.yaml \
  --manifest /tmp/manifest.json

# in a release (docker/k8s), gated behind ALLOW_BOOTSTRAP=true
bin/lightning eval 'Lightning.Setup.bootstrap("/etc/lightning/state.yaml")'
```

Re-running a scenario is **idempotent**: users are matched by email, credentials
by owner+name, and projects/workflows/jobs/triggers/edges get deterministic ids
derived from their names, so everything upserts instead of duplicating. Renames
are the exception — a renamed record gets a new id and the old record is left
behind (pin an explicit `id:` on anything you plan to rename).

## Manifest

`--manifest PATH` (or `manifest: path` on the Elixir APIs) writes a JSON file
with everything a script or test harness needs to drive the instance: user
emails and API tokens, project/workflow/job ids, and trigger webhook paths
(`/i/<trigger-id>`).

## File format

Top-level keys: `users`, `credentials`, `projects`. All lists optional.

Every key at every level (except inside workflow/trigger/job/edge maps, which
pass through to the provisioner — see below) is checked against an allow-list. A
typo'd or unsupported key raises immediately, naming the bad key, rather than
being silently ignored.

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

```yaml
workflows:
  - name: My Workflow # required
    trigger: # map, or "none" for a trigger-less workflow
      type: webhook # webhook (default) | cron | kafka
    jobs:
      - name: Job One # required
        adaptor: '@openfn/language-common@latest' # default
        body: 'fn(state => state);' # default
        credential: my-credential # optional, a credential name
    edges:
      - from: trigger # "trigger" (default) or a job name
        to: Job One # required, a job name
        condition:
          always # default: "always" from trigger,
          # "on_job_success" from a job
```

Trigger, job and edge maps are **passed through** to the provisioning document
after the conveniences above are resolved, so any field the provisioner accepts
works directly, e.g.:

```yaml
trigger:
  type: webhook
  webhook_reply: after_completion # sync-mode webhook replies
  custom_path: my-hook
# or
trigger:
  type: cron
  cron_expression: "0 * * * *"
  enabled: false
# and on edges:
edges:
  - from: a
    to: b
    condition: js_expression
    condition_expression: "state.data.ok"
    condition_label: only when ok
```

Unknown fields are rejected by the provisioner's validation, so typos fail
loudly rather than being silently dropped.

### Environment interpolation

Any string value anywhere in the file may reference `${env:SOME_VAR}`; the
variable is resolved when the scenario runs and it is an error for it to be
unset. Use this to keep secrets out of committed scenario files.

Interpolation is explicit — only the `${env:...}` form is replaced. Plain
`${...}` is left alone, so JS template literals in job bodies (`${id}`,
`${HOME}`, `${state.data}`) can never collide with it.

## Safety

Bootstrapping creates users (including superusers) and is disabled outside
dev/test. Releases must opt in with `ALLOW_BOOTSTRAP=true`.
