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
│   └── canonical_workflow.yaml         ← workflow-level kitchen sink for v1 parse + parity
└── v2/
    ├── canonical_project.yaml          ← project-level kitchen sink for v2 pull
    └── canonical_workflow.yaml         ← workflow-level kitchen sink for v2 round-trip + parity
```

## Consumers

| Fixture                            | Consumed by                                                                                                                                                                                                                                                      |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `v1/canonical_project.yaml`        | `test/integration/cli_deploy_test.exs` — v1 deploy create                                                                                                                                                                                                        |
| `v1/canonical_update_project.yaml` | `test/integration/cli_deploy_test.exs` — v1 deploy update                                                                                                                                                                                                        |
| `v1/canonical_workflow.yaml`       | `assets/test/yaml/util.test.ts`, `assets/test/yaml/v2.test.ts` (cross-format parity), `assets/test/collaborative-editor/.../TemplatePanel.test.tsx`, `assets/test/collaborative-editor/.../YAMLImportPanel.test.tsx`                                             |
| `v2/canonical_project.yaml`        | `test/integration/cli_deploy_test.exs` — v2 pull byte-equality                                                                                                                                                                                                   |
| `v2/canonical_workflow.yaml`       | `assets/test/yaml/v2.test.ts` (round-trip), `assets/test/yaml/util.test.ts`, `assets/test/yaml/v2.test.ts` (cross-format parity), `assets/test/collaborative-editor/.../TemplatePanel.test.tsx`, `assets/test/collaborative-editor/.../YAMLImportPanel.test.tsx` |

## Kitchen-sink design

`canonical_workflow.yaml` (in both `v1/` and `v2/`) is the single, comprehensive
witness for every feature the format supports — multi-trigger (webhook, cron,
kafka), kafka config, `cron_cursor`, `webhook_reply`, JS-expression edge with
`label` and `disabled`, branching with all condition types (`always`,
`on_job_success`, `on_job_failure`, `js_expression`).

Adding a new feature to the portability format means **adding a case to the
canonical workflow**. The byte-equality and parse tests will fail loudly until
the new feature is represented — silent coverage gaps are not possible under
this design.

The v1 and v2 files describe the same workflow in two formats; the cross-format
parity test in `assets/test/yaml/v2.test.ts` and `assets/test/yaml/util.test.ts`
asserts they parse to structurally equivalent specs.

## Editing notes

- **Kitchen-sink fixtures are byte-equality witnesses** for an emitter.
  `v2/canonical_project.yaml` must match exactly what Lightning emits for the
  project built by `canonical_project_fixture/0` (see
  `test/support/fixtures/projects_fixtures.ex`); `v2/canonical_workflow.yaml` is
  the spec witness referenced from `lib/lightning/workflows/yaml_format/v2.ex`
  and `assets/js/yaml/v2.ts`. Touching either requires updating its emit source
  in lockstep.
- **Add features to both `v1/canonical_workflow.yaml` and
  `v2/canonical_workflow.yaml` together.** The cross-format parity test pairs
  them; a v1-only or v2-only addition will fail parity.
- **The v2 spec is still a draft** (`docs#774`); the `@openfn/cli` lexicon
  pinned in `lib/lightning/workflows/yaml_format/v2.ex` is the authoritative
  source for field names.
