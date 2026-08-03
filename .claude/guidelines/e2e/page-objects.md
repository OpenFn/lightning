# Page Object Model (POM) Best Practices

## Overview

The Page Object Model pattern encapsulates page structure and interactions,
making tests more maintainable and readable. Lightning uses a hierarchical POM
structure with base classes, page-specific models, and reusable component
models.

## POM Architecture

### Directory Structure

```
assets/test/e2e/pages/
├── base/
│   ├── index.ts                 # Re-export base classes
│   └── liveview.page.ts         # Base class for LiveView pages
├── components/
│   ├── index.ts                 # Re-export component POMs
│   ├── job-form.page.ts         # Job form component
│   └── workflow-diagram.page.ts # Workflow diagram component
├── index.ts                     # Re-export all page objects
├── login.page.ts                # Login page
├── projects.page.ts             # Projects list page
├── workflow-edit.page.ts        # Workflow editor (LiveView)
└── workflow-collab.page.ts      # NEW: Collaborative editor (React)
```

### Class Hierarchy

```
Page
  ↓
LiveViewPage (base/liveview.page.ts)
  ↓
  ├── WorkflowEditPage (workflow-edit.page.ts)
  ├── ProjectsPage (projects.page.ts)
  └── WorkflowsPage (workflows.page.ts)

LiveViewPage
  ↓
Component POMs
  ├── WorkflowDiagramPage (components/workflow-diagram.page.ts)
  └── JobFormPage (components/job-form.page.ts)
```

## Base Classes

### LiveViewPage Base Class

Provides common functionality for Phoenix LiveView pages:

```typescript
// pages/base/liveview.page.ts
import { expect } from '@playwright/test';
import type { Page, Locator } from '@playwright/test';

export abstract class LiveViewPage {
  protected baseSelectors = {
    phoenixMain: 'div[data-phx-main]',
    flashMessage: '[id^="flash-"][phx-hook="Flash"]',
  };

  constructor(protected page: Page) {}

  /**
   * Wait for Phoenix LiveView connection.
   * See `.claude/guidelines/e2e/phoenix-liveview.md §LiveView waits` for the canonical implementation and rationale.
   */
  async waitForConnected(): Promise<void> {
    const locator = this.page.locator(this.baseSelectors.phoenixMain);
    await expect(locator).toBeVisible();
    await expect(locator).toHaveClass(/phx-connected/);
  }

  /**
   * Wait for WebSocket to settle
   */
  async waitForSocketSettled(): Promise<void> {
    await this.page.waitForFunction(() => {
      return new Promise(resolve => {
        window.liveSocket.socket.ping(resolve);
      });
    });
  }

  /**
   * Assert flash message is visible
   */
  async expectFlashMessage(text: string): Promise<void> {
    const flashMessage = this.page
      .locator(this.baseSelectors.flashMessage)
      .filter({ hasText: text });
    await expect(flashMessage).toBeVisible();
  }

  /**
   * Click sidebar menu item
   */
  async clickMenuItem(itemText: string): Promise<void> {
    await this.page
      .locator('#side-menu')
      .getByRole('link', { name: itemText })
      .click();
  }
}
```

**Key Principles:**
- Use `protected page: Page` for subclass access
- Define common selectors in `baseSelectors`
- Provide reusable utility methods
- Mark class as `abstract` to prevent direct instantiation

## Page-Level POMs

### Structure Pattern

```typescript
// pages/workflow-edit.page.ts
import { expect } from '@playwright/test';
import type { Page, Locator } from '@playwright/test';
import { LiveViewPage } from './base';
import { WorkflowDiagramPage, JobFormPage } from './components';

export class WorkflowEditPage extends LiveViewPage {
  // Component POMs
  readonly diagram: WorkflowDiagramPage;

  // Selectors specific to this page
  protected selectors = {
    topBar: '[data-testid="top-bar"]',
    saveButton: 'button:has-text("Save")',
    runButton: '[data-testid="run-workflow-btn"]',
    workflowNameInput: 'input[name="workflow[name]"]',
    unsavedChangesIndicator: '.absolute.-m-1.rounded-full.bg-danger-500',
  };

  constructor(page: Page) {
    super(page);
    // Initialize component POMs
    this.diagram = new WorkflowDiagramPage(page);
  }

  /**
   * Factory method for component POMs with parameters
   */
  jobForm(jobIndex: number = 0): JobFormPage {
    return new JobFormPage(this.page, jobIndex);
  }

  /**
   * Page-specific actions
   */
  async clickSaveWorkflow(): Promise<void> {
    const topBar = this.page.locator(this.selectors.topBar);
    const saveButton = topBar.locator(this.selectors.saveButton);
    await expect(saveButton).toBeVisible();
    await saveButton.click();
  }

  async setWorkflowName(name: string): Promise<void> {
    const nameInput = this.page.locator(this.selectors.workflowNameInput);
    await expect(nameInput).toBeVisible();
    await nameInput.fill(name);
  }

  /**
   * Return locators for flexible assertions in tests
   */
  unsavedChangesIndicator(): Locator {
    const topBar = this.page.locator(this.selectors.topBar);
    return topBar.locator(this.selectors.unsavedChangesIndicator);
  }
}
```

**Key Principles:**
- Extend `LiveViewPage` for Phoenix LiveView pages
- Initialize component POMs in constructor
- Define page-specific selectors in `selectors` object
- Provide high-level methods for user actions
- Return `Locator` for flexible assertions

### Using the Page Object

```typescript
import { WorkflowEditPage } from '../pages';

test('edit workflow', async ({ page }) => {
  const workflowEdit = new WorkflowEditPage(page);

  await page.goto('/w/123');
  await workflowEdit.waitForConnected();

  // Use page methods
  await workflowEdit.setWorkflowName('Updated Name');

  // Use component methods
  await workflowEdit.diagram.clickNode('Job 1');

  // Use factory methods
  await workflowEdit.jobForm(0).nameInput.fill('New Job Name');

  // Save and verify
  await workflowEdit.clickSaveWorkflow();
  await workflowEdit.expectFlashMessage('Workflow saved');

  // Use locator methods for assertions
  await expect(workflowEdit.unsavedChangesIndicator()).not.toBeVisible();
});
```

## Component POMs

### Component Pattern

Components are reusable UI elements that appear in multiple pages:

```typescript
// pages/components/workflow-diagram.page.ts
import { expect } from '@playwright/test';
import type { Page, Locator } from '@playwright/test';
import { LiveViewPage } from '../base';

export class WorkflowDiagramPage extends LiveViewPage {
  protected selectors = {
    reactFlow: '.react-flow',
    viewport: '.react-flow__viewport',
    nodes: '.react-flow__node',
    jobNodes: '.react-flow__node-job',
    placeholderNode: '.react-flow__node-placeholder',
    nodeConnector: '[data-handleid="node-connector"]',
    fitViewButton: '.react-flow__controls-button[data-tooltip="Fit view"]',
  };

  constructor(page: Page) {
    super(page);
  }

  /**
   * Get node by visible name/text
   */
  getNodeByName(nodeName: string): Locator {
    return this.page
      .locator(this.selectors.nodes)
      .filter({ hasText: nodeName });
  }

  /**
   * Click on a node
   */
  async clickNode(nodeName: string): Promise<void> {
    const node = this.getNodeByName(nodeName);
    await expect(node).toBeVisible();
    await node.click();
  }

  /**
   * Verify node exists
   */
  async verifyNodeExists(nodeName: string): Promise<void> {
    await expect(this.getNodeByName(nodeName)).toBeVisible();
  }

  /**
   * Click plus button on node to add connection
   */
  async clickNodePlusButtonOn(nodeName: string): Promise<void> {
    const node = this.getNodeByName(nodeName);
    await node.hover(); // Show the plus button

    const plusButton = node.locator(this.selectors.nodeConnector);
    await expect(plusButton).toBeVisible();
    await plusButton.click();
  }

  /**
   * Verify React Flow is present
   */
  async verifyReactFlowPresent(): Promise<void> {
    await expect(this.page.locator(this.selectors.reactFlow)).toBeVisible();
    await expect(this.page.locator(this.selectors.viewport)).toBeVisible();
  }

  /**
   * Get all nodes
   */
  get allNodes(): Locator {
    return this.page.locator(this.selectors.nodes);
  }

  /**
   * Verify node count
   */
  async verifyNodeCount(expectedCount: number): Promise<void> {
    await expect(this.allNodes).toHaveCount(expectedCount);
  }
}
```

**Key Principles:**
- Extend `LiveViewPage` for LiveView components
- Focus on component-specific interactions
- Provide both actions and assertions
- Use getters for frequently accessed locators
- Return locators for flexible usage

### Component with Parameters

```typescript
// pages/components/job-form.page.ts
import { expect } from '@playwright/test';
import type { Page, Locator } from '@playwright/test';
import { LiveViewPage } from '../base';

export class JobFormPage extends LiveViewPage {
  protected selectors = {
    form: '[id^="workflow-form-"]',
    header: 'h2',
    nameInput: 'input[name*="[name]"]',
    adaptorSelect: 'select[name*="[adaptor]"]',
    versionSelect: 'select[name*="[version]"]',
  };

  constructor(
    page: Page,
    private jobIndex: number
  ) {
    super(page);
  }

  /**
   * Get the form container for this specific job
   */
  get workflowForm(): Locator {
    return this.page.locator(this.selectors.form).nth(this.jobIndex);
  }

  /**
   * Get header text
   */
  get header(): Locator {
    return this.workflowForm.locator(this.selectors.header);
  }

  /**
   * Get name input
   */
  get nameInput(): Locator {
    return this.workflowForm.locator(this.selectors.nameInput);
  }

  /**
   * Get adaptor select
   */
  get adaptorSelect(): Locator {
    return this.workflowForm.locator(this.selectors.adaptorSelect);
  }

  /**
   * Get version select
   */
  get versionSelect(): Locator {
    return this.workflowForm.locator(this.selectors.versionSelect);
  }
}
```

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

