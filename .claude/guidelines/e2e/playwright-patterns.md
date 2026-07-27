# Playwright Patterns (Lightning index)

This file is an index. For generic Playwright behavior — auto-waiting, web-first assertions, semantic locators (`getByRole`/`getByLabel`/`getByTestId`), network interception, file upload/download, accessibility snapshots — refer to the upstream [Playwright docs](https://playwright.dev/docs/intro). Opus 4.7 already produces these patterns correctly by default; we do not re-document them here.

Lightning-specific Playwright usage lives in dedicated files. Use this table to locate what you need.

## Where to find each pattern

| Pattern | File |
|---|---|
| Lightning e2e setup, dev server boot, port 4003, test data, `bin/e2e` | [`../e2e-testing.md`](../e2e-testing.md) |
| LiveView connection waits (`waitForConnected`, `phx-connected`, `phx-change`, `waitForSocketSettled`, flash messages, Monaco hook) | [`./phoenix-liveview.md §LiveView waits`](./phoenix-liveview.md) |
| Multi-context collaborative setup, Yjs sync verification, presence, offline/online transitions, Phoenix Channel WebSocket debugging | [`./collaborative-testing.md`](./collaborative-testing.md) |
| Page Object Model conventions — LiveViewPage base class, component POMs (WorkflowDiagramPage, JobFormPage), composition, factory methods | [`./page-objects.md`](./page-objects.md) |

## Lightning defaults worth remembering

- Workflow edit URLs take the form `/w/:id` or `/projects/:project_id/w/:id`; collaborative editor routes are `/collab/w/:id`.
- Every LiveView navigation opens a new WebSocket — re-call `waitForConnected()` after link clicks that cross LiveViews.
- Prefer `getByTestId` only when semantic locators (`getByRole`, `getByLabel`) cannot uniquely identify the target. Lightning seeds `data-testid` on diagram primitives (`workflow-canvas`, `workflow-diagram`, nodes) where role/label is ambiguous.
