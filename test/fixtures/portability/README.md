## Fixtures: portability

These fixtures back the v1 ↔ v2 portability work (issue #4718). They are the
spec witness for both formats: any change to either `YamlFormat.V1` or
`YamlFormat.V2` field set must show up in the corresponding canonical fixture.
**Read these before reading the format modules.**

### Layout

```
portability/
├── v1/                     Lightning's legacy format (parse-only after Phase 4)
│   ├── canonical_project.yaml                  ← kept for existing project-import regression tests
│   ├── canonical_update_project.yaml           ← kept for existing project-import regression tests
│   ├── webhook_reply_and_cron_cursor_project.yaml ← kept for existing project-import regression tests
│   ├── canonical_workflow.yaml                 ← v1 representation of the v2 kitchen sink
│   └── scenarios/                              ← v1 representation of each v2 scenario, paired by filename
└── v2/                     CLI-aligned portability format (export + import)
    ├── canonical_project.yaml                  ← project-level kitchen sink (placeholder, see below)
    ├── canonical_workflow.yaml                 ← workflow-level kitchen sink
    └── scenarios/                              ← targeted, single-feature workflows
```

A scenario lives in **both** `v1/scenarios/` and `v2/scenarios/` under the same
filename. The two files represent the same workflow in two formats; the
cross-format equivalence tests assert they parse to identical Workflow records.

### Canonical kitchen-sink fixtures

`v2/canonical_workflow.yaml` and `v2/canonical_project.yaml` exercise every
public field on the V2 spec in a single document. They double as living
documentation — a new contributor's first stop should be one `cat` of each.
Coverage assertions in `test/lightning/workflows/yaml_format_v2_test.exs` walk
the parsed canonical map and fail loudly if any documented field is missing.

The exact byte contents are placeholders pending definitive examples from the
spec author; the coverage assertion is what enforces completeness regardless of
who authored the bytes.

### Scenarios

- `simple-webhook.yaml` — a single webhook trigger feeding a single step.
- `cron-with-cursor.yaml` — cron trigger with a `cron_cursor` step reference.
- `js-expression-edge.yaml` — an edge whose condition is a JS expression.
- `multi-trigger.yaml` — webhook and cron triggers in one workflow.
- `kafka-trigger.yaml` — kafka trigger with hosts/topics.
- `branching-jobs.yaml` — one source step with multiple `next:` targets.

### v2 field names are PROVISIONAL

The v2 spec is a draft (`docs#774`) and the `@openfn/cli` parser is the
authoritative source. The field names committed to here are documented at the
top of `lib/lightning/workflows/yaml_format/v2.ex`. Changing a field name is a
one-line edit in that module plus a fixture refresh.
