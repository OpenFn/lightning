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

### users

| key          | required | default            | notes                                 |
| ------------ | -------- | ------------------ | ------------------------------------- |
| `email`      | yes      |                    | matched on re-run                     |
| `first_name` |          | derived from email |                                       |
| `last_name`  |          | `User`             |                                       |
| `password`   |          | `welcome12345`     |                                       |
| `superuser`  |          | `false`            |                                       |
| `api_token`  |          | `false`            | `true` = generate/reuse, see manifest |

Users are created confirmed.

### credentials

| key      | required | default | notes                                  |
| -------- | -------- | ------- | -------------------------------------- |
| `name`   | yes      |         | unique per scenario; matched on re-run |
| `owner`  | yes      |         | email of a user declared above         |
| `schema` |          | `raw`   | e.g. `dhis2`, `http`, `postgresql`     |
| `body`   |          | `{}`    | secret values; supports `${ENV_VAR}`   |

Existing credentials (matched by owner+name) are reused as-is; bodies are not
updated on re-run.

### projects

| key           | required | notes                                |
| ------------- | -------- | ------------------------------------ |
| `name`        | yes      | url-safe (lowercase, digits, dashes) |
| `members`     | yes      | at least one `role: owner`           |
| `credentials` |          | names to expose to this project      |
| `workflows`   |          |                                      |

Members: `{ email, role }` with role one of `owner`, `admin`, `editor`, `viewer`
(default `editor`). Re-runs add missing members and correct drifted roles, but
never remove anyone.

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

Any string value anywhere in the file may reference `${SOME_ENV_VAR}`; the
variable is resolved when the scenario runs and it is an error for it to be
unset. Use this to keep secrets out of committed scenario files.

Only `SCREAMING_SNAKE_CASE` names are treated as env references, so JS template
literals in job bodies (`${count}`, `${state.data}`) pass through untouched.
Avoid uppercase `${...}` literals in job bodies — they will be interpolated.

## Safety

Bootstrapping creates users (including superusers) and is disabled outside
dev/test. Releases must opt in with `ALLOW_BOOTSTRAP=true`.
