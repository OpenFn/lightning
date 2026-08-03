# Page Object Model (POM) Best Practices

Lightning's e2e suite uses a hierarchical POM structure: one abstract LiveView base class,
page-level models that extend it, and standalone component models they compose.

## POM Architecture

### Directory Structure

`ls assets/test/e2e/pages/` — three directories deep at most: `base/`, `components/`, and the
page-level POMs at the root, each with an `index.ts` of named re-exports.

### Class Hierarchy

There is one inheritance chain, and component POMs are **not** in it.

```
LiveViewPage (abstract — base/liveview.page.ts)
  ├── LoginPage                  (login.page.ts)
  ├── ProjectsPage               (projects.page.ts)
  ├── WorkflowsPage              (workflows.page.ts)
  └── WorkflowCollaborativePage  (workflow-collab.page.ts)

Standalone, constructed with `page`, composed by the above:
  WorkflowDiagramPage            (components/workflow-diagram.page.ts)
    ├── WorkflowDiagramNodesPage (components/workflow-diagram-nodes.page.ts)
    └── WorkflowDiagramEdgesPage (components/workflow-diagram-edges.page.ts)
  JobInspectorPage               (components/job-inspector.page.ts)
```

## Base Classes

### LiveViewPage Base Class

Provides common functionality for Phoenix LiveView pages.
`assets/test/e2e/pages/base/liveview.page.ts` is 104 lines. Read it rather than a copy — this
file used to carry a transcription of it that had drifted, writing `toHaveClass` where the
source says `toContainClass`, and omitting `waitForEventAttached` entirely.

What the base class gives every page object:

| Member | Purpose |
|---|---|
| `baseSelectors` | `div[data-phx-main]` and `[id^="flash-"][phx-hook="Flash"]` |
| `waitForConnected()` | Waits for `phx-connected` on the main container |
| `waitForSocketSettled()` | Pings the socket. Its own docstring says this still needs verifying |
| `waitForEventAttached(locator, eventType, timeout)` | Waits for a LiveView handler to attach |
| `expectFlashMessage(text)` | Asserts a flash containing `text` |
| `clickMenuItem(text)` | Clicks a `#side-menu` link by name |

See `.claude/guidelines/e2e/phoenix-liveview.md §LiveView waits` for when to use each.

**Key Principles:**
- Use `protected page: Page` for subclass access
- Define common selectors in `baseSelectors`
- Provide reusable utility methods
- Mark class as `abstract` to prevent direct instantiation

## Page-Level POMs

### Structure Pattern

A page-level POM extends `LiveViewPage`, declares its own `selectors`, composes its component
POMs, and exposes high-level actions. Read `pages/workflow-collab.page.ts` for the current
example — `WorkflowCollaborativePage` is the one full-page POM in the suite, and
`pages/login.page.ts`, `projects.page.ts` and `workflows.page.ts` are smaller instances of the
same shape.

**Key Principles:**
- Extend `LiveViewPage` for Phoenix LiveView pages
- Initialize component POMs in constructor
- Define page-specific selectors in `selectors` object
- Provide high-level methods for user actions
- Return `Locator` for flexible assertions

## Component POMs

### Component Pattern

Components are reusable UI elements that appear in multiple pages. The suite's component POMs
live in `pages/components/`. Read one before writing another —
`workflow-diagram.page.ts` is 46 lines and shows the whole shape: a plain class taking `page`,
a `selectors` object, two `readonly` sub-POMs, and two methods.

Selector strategy for the diagram is **React Flow CSS classes**, not testids:
`.react-flow`, `.react-flow__viewport`, `.react-flow__node`, `.react-flow__node-job`,
`.react-flow__node-trigger`, `.react-flow__node-placeholder`, plus
`[data-handleid="node-connector"]` for the plus handle. The node and edge queries live in
`workflow-diagram-nodes.page.ts` and `workflow-diagram-edges.page.ts`, not on the parent.

**Key Principles:**
- Component POMs take `page` and stand alone — **do not** extend `LiveViewPage`. That base
  class is for whole LiveView pages; a component has no connection lifecycle of its own.
  `WorkflowDiagramPage`, `WorkflowDiagramNodesPage`, `WorkflowDiagramEdgesPage` and
  `JobInspectorPage` all follow this.
- Compose them from the page object that owns them, as a `readonly` field or a getter
- Focus on component-specific interactions
- Provide both actions and assertions
- Use getters for frequently accessed locators
- Return locators for flexible usage

## Composition Patterns

### Component Composition

Two shapes are in use, and they differ in when the child is built.

**`readonly` fields, built in the constructor.** `WorkflowDiagramPage`
(`workflow-diagram.page.ts:11-24`) holds its two sub-POMs this way:

```typescript
export class WorkflowDiagramPage {
  readonly edges: WorkflowDiagramEdgesPage;
  readonly nodes: WorkflowDiagramNodesPage;

  constructor(protected page: Page) {
    this.edges = new WorkflowDiagramEdgesPage(page);
    this.nodes = new WorkflowDiagramNodesPage(page);
  }
}
```

**A getter, built on access.** `WorkflowCollaborativePage`
(`workflow-collab.page.ts:34-36`) does it lazily instead — see §Getter factories.

Both are fine. Use `readonly` fields when the child is always needed, a getter when it is
not.

Note that `WorkflowDiagramPage` does **not** extend `LiveViewPage`, and neither do its two
sub-POMs. Component POMs in this suite are standalone.

### Getter factories, and parameters on locators

There are no parameterised component constructors in this suite. Two patterns cover the same
ground, and both are in the code.

**A getter that builds the component on demand.** `workflow-collab.page.ts:34-36`:

```typescript
get jobInspector(): JobInspectorPage {
  return new JobInspectorPage(this.page);
}
```

The component takes only `page` (`job-inspector.page.ts:11`), so the getter needs no
arguments. Reach for this when the component is a singleton on the page.

**Parameters on the locator method, not the constructor.** `WorkflowDiagramNodesPage` takes
only `page` and puts the parameter where the query is:

```typescript
getByName(name: string): Locator          // workflow-diagram-nodes.page.ts:27
getJobByIndex(index: number): Locator     // :36
async clickJobByIndex(index: number)      // :137
```

This is what replaced the old `jobForm(index)` factory. One instance of the component POM
handles every node, and there is no per-instance state to get wrong. Prefer it.

`WorkflowCollaborativePage` composes only `jobInspector`, so a test that needs the diagram
constructs `WorkflowDiagramPage` alongside it — which is what
`specs/collaborative/edge-validation.spec.ts:41,48` does.

```typescript
const collabEditor = new WorkflowCollaborativePage(page);
const diagram = new WorkflowDiagramPage(page);

await collabEditor.open({ projectId, workflowId });

await diagram.nodes.clickJobByIndex(0);
await collabEditor.jobInspector.setName('Fetch Data');
```

## LiveView-Specific Waiting in POMs

Lightning page objects should override `goto` to include the LiveView connect wait. See `.claude/guidelines/e2e/phoenix-liveview.md §LiveView waits` for the full set of LiveView wait primitives.

```typescript
class WorkflowEditPage extends LiveViewPage {
  async goto(workflowId: string): Promise<void> {
    await this.page.goto(`/w/${workflowId}`);
    await this.waitForConnected();
    await this.page.waitForLoadState('networkidle');
  }

  async waitForWorkflowSaved(): Promise<void> {
    await this.waitForSocketSettled();
    await this.expectFlashMessage('Workflow saved');
  }
}
```

## Index Files

`pages/index.ts` is a flat list of **named** re-exports, not `export *`. Six lines today.
Add your class to it so tests can `import { ... } from '../pages'`, and read the file
rather than a copy of it — `pages/index.ts`, `pages/base/index.ts`,
`pages/components/index.ts`.

