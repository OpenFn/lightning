# Fixtures: portability

YAML fixtures for Lightning's portability format — the single-file project
representation used to bundle a project for transfer between environments. These
fixtures are read by the integration tests (Elixir) and the YAML test suites
(TypeScript) that exercise parse, emit, and pull/deploy paths.

Two formats live here:

- **v1** — Lightning's legacy format. Parse-only: Lightning no longer emits v1
  (the only emitter today is `lib/lightning/workflows/yaml_format/v2.ex`), but
  the frontend's `assets/js/yaml/v1.ts` still parses v1 docs so old projects can
  be loaded.
- **v2** — the current portability format, aligned with the `@openfn/cli`
  lexicon (`portability.d.ts`). Lightning emits and parses v2; the frontend
  emits and parses v2.

## Layout

```
portability/
├── v1/
│   ├── canonical_project.yaml          ← project-level kitchen sink for v1 deploy
│   ├── canonical_update_project.yaml   ← v1 deploy "update existing project" payload
│   └── scenarios/                      ← single-feature workflows, paired with v2/scenarios
└── v2/
    ├── canonical_project.yaml          ← project-level kitchen sink for v2 pull
    ├── canonical_workflow.yaml         ← workflow-level kitchen sink for v2 round-trip
    └── scenarios/                      ← single-feature workflows, paired with v1/scenarios
```

Each filename under `v1/scenarios/` has a sibling under `v2/scenarios/`. The two
files describe the same workflow in two formats — frontend parity tests parse
each side and assert structural equivalence.

## Consumers

| Fixture                            | Consumed by                                                                                                                                                                                                          |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `v1/canonical_project.yaml`        | `test/integration/cli_deploy_test.exs` — v1 deploy create                                                                                                                                                            |
| `v1/canonical_update_project.yaml` | `test/integration/cli_deploy_test.exs` — v1 deploy update                                                                                                                                                            |
| `v2/canonical_project.yaml`        | `test/integration/cli_deploy_test.exs` — v2 pull byte-equality                                                                                                                                                       |
| `v2/canonical_workflow.yaml`       | `assets/test/yaml/v2.test.ts` — v2 state ↔ YAML ↔ spec round-trip                                                                                                                                                  |
| `v{1,2}/scenarios/*.yaml`          | `assets/test/yaml/util.test.ts`, `assets/test/yaml/v2.test.ts` (cross-format parity), `assets/test/collaborative-editor/.../TemplatePanel.test.tsx`, `assets/test/collaborative-editor/.../YAMLImportPanel.test.tsx` |

## Scenarios

Each scenario isolates one feature so a regression in a single area doesn't mask
others.

- `simple-webhook.yaml` — single webhook trigger feeding a single step.
- `cron-with-cursor.yaml` — cron trigger with a `cron_cursor` step reference.
- `js-expression-edge.yaml` — edge whose condition is a JS expression body.
- `multi-trigger.yaml` — webhook and cron triggers in one workflow.
- `kafka-trigger.yaml` — kafka trigger with hosts/topics.
- `branching-jobs.yaml` — one source step with multiple `next:` targets.

## Editing notes

- **Kitchen-sink fixtures are byte-equality witnesses** for an emitter.
  `v2/canonical_project.yaml` must match exactly what Lightning emits for the
  project built by `canonical_project_fixture/0` (see
  `test/support/fixtures/projects_fixtures.ex`); `v2/canonical_workflow.yaml` is
  the spec witness referenced from `lib/lightning/workflows/yaml_format/v2.ex`
  and `assets/js/yaml/v2.ts`. Touching either requires updating its emit source
  in lockstep.
- **Scenarios are paired by filename.** Adding a scenario means adding a v1 and
  a v2 file under the same name; the parity test will pick it up automatically
  once the name is added to the `SCENARIOS` array in the consuming test files.
- **The v2 spec is still a draft** (`docs#774`); the `@openfn/cli` lexicon
  pinned in `lib/lightning/workflows/yaml_format/v2.ex` is the authoritative
  source for field names.
