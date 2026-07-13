# Bootstrap scenarios

A **scenario** is a declarative description of the data Lightning should boot
into. It's an alternative to the fixed `setup_demo` fixture: instead of always
getting the OpenHIE/DHIS2 demo, you define the exact users, projects, workflows
and jobs you want.

Scenarios live here as `*.yaml`, `*.yml` or `*.json` files and are loaded by
[`../load_scenario.exs`](../load_scenario.exs) into
[`Lightning.Bootstrap`](../../../lib/lightning/bootstrap.ex).

## Usage

```bash
# Boot into a named scenario (looks up scenarios/<name>.{yaml,yml,json})
bin/e2e start --scenario example

# Or point at any file
bin/e2e start --scenario /path/to/my-scenario.yaml

# Rebuild the snapshot for a scenario, then fast-reset between runs
bin/e2e setup --scenario example
bin/e2e reset --scenario example        # fast restore from the scenario snapshot

# The SCENARIO env var works everywhere the flag does
SCENARIO=example bin/e2e start
```

Each scenario gets its **own snapshot** at
`/tmp/lightning_e2e_snapshot__<name>.sql`, so switching scenarios doesn't
clobber another's data. Without `--scenario`, `bin/e2e` behaves exactly as
before (`setup_demo`, snapshot at `/tmp/demo_data_snapshot.sql`).

## Format

```yaml
users: # required if any project has members
  - email: amy@openfn.org # required, unique — used to reference the user
    first_name: Amy # default: capitalized local-part of email
    last_name: Admin # default: "User"
    password: welcome12345 # default: "welcome12345"
    superuser: false # default: false

projects:
  - name: my-project # required
    members: # default: none (but a project needs one to own workflows)
      - { email: amy@openfn.org, role: owner } # role: owner | admin | editor | viewer
    workflows:
      - name: My Workflow # required
        trigger: # default: a webhook trigger. Use `none` to skip.
          type: webhook # webhook | cron | kafka  (default: webhook)
          cron_expression: '* * * * *' # only for type: cron
        jobs:
          - name: Job 1 # required, unique within the workflow — referenced by edges
            adaptor: '@openfn/language-common@latest' # default shown
            body: 'fn(state => state);' # default shown
        edges:
          # `from: trigger` (or omit `from`) connects from the workflow trigger.
          - { from: trigger, to: Job 1, condition: always }
          - { from: Job 1, to: Job 2, condition: on_job_success }
          # condition: always | on_job_success | on_job_failure | js_expression
          # default condition: `always` from a trigger, `on_job_success` from a job
          # enabled: true (default)
```

Jobs and edges are optional — a workflow with just a trigger is valid. Edges
reference jobs by their `name`, and the trigger by the literal `trigger`.

The workflow "actor" (the user recorded as making the changes) is the
highest-privileged member of the owning project.

## Notes / current limitations

- Runs in `MIX_ENV=dev` against the E2E database, using the real context
  functions — the resulting data behaves like UI-created data.
- Credentials, collections, and pre-seeded run history are **not yet**
  expressible; extend `Lightning.Bootstrap` if you need them.
- JSON files use the same key names as the YAML above.
