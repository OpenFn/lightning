## Fixtures: portability

These fixtures back the v1 ↔ v2 portability work (issue #4718). They are spec
witnesses for both formats and are consumed by the frontend YAML tests
(`assets/test/yaml/`) and a couple of regression integration tests.

### Layout

```
portability/
├── v1/                     Lightning's legacy format (parse-only after Phase 4)
│   ├── canonical_project.yaml                  ← used by test/integration/cli_deploy_test.exs
│   ├── canonical_update_project.yaml           ← used by test/integration/cli_deploy_test.exs
│   ├── canonical_workflow.yaml                 ← v1 representation of the v2 kitchen sink
│   └── scenarios/                              ← v1 representation of each v2 scenario, paired by filename
└── v2/                     CLI-aligned portability format
    ├── canonical_workflow.yaml                 ← workflow-level kitchen sink
    └── scenarios/                              ← targeted, single-feature workflows
```

A scenario lives in **both** `v1/scenarios/` and `v2/scenarios/` under the same
filename. The two files represent the same workflow in two formats; frontend
tests parse each side and assert structural equivalence.

### Scenarios

- `simple-webhook.yaml` — a single webhook trigger feeding a single step.
- `cron-with-cursor.yaml` — cron trigger with a `cron_cursor` step reference.
- `js-expression-edge.yaml` — an edge whose condition is a JS expression.
- `multi-trigger.yaml` — webhook and cron triggers in one workflow.
- `kafka-trigger.yaml` — kafka trigger with hosts/topics.
- `branching-jobs.yaml` — one source step with multiple `next:` targets.

### v2 field names are PROVISIONAL

The v2 spec is a draft (`docs#774`) and the `@openfn/cli` parser is the
authoritative source.
