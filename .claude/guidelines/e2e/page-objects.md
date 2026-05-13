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

**Usage:**
```typescript
test('configure job', async ({ page }) => {
  const workflowEdit = new WorkflowEditPage(page);

  await page.goto('/w/123');
  await workflowEdit.waitForConnected();

  // Access specific job form by index
  const job1 = workflowEdit.jobForm(0);
  await job1.nameInput.fill('Fetch Data');
  await job1.adaptorSelect.selectOption('@openfn/language-http');

  const job2 = workflowEdit.jobForm(1);
  await job2.nameInput.fill('Transform Data');
});
```

## Composition Patterns

### Component Composition

Page objects compose component objects:

```typescript
// Page contains multiple components
export class WorkflowEditPage extends LiveViewPage {
  readonly diagram: WorkflowDiagramPage;
  readonly sidebar: WorkflowSidebarPage;
  readonly inspector: JobInspectorPage;

  constructor(page: Page) {
    super(page);
    this.diagram = new WorkflowDiagramPage(page);
    this.sidebar = new WorkflowSidebarPage(page);
    this.inspector = new JobInspectorPage(page);
  }
}

// Usage
test('edit workflow', async ({ page }) => {
  const workflowEdit = new WorkflowEditPage(page);

  await page.goto('/w/123');
  await workflowEdit.waitForConnected();

  // Use composed components
  await workflowEdit.diagram.clickNode('Job 1');
  await workflowEdit.inspector.setJobName('Updated Name');
  await workflowEdit.sidebar.expandSection('Settings');
});
```

### Factory Methods

Create component instances with parameters:

```typescript
export class WorkflowEditPage extends LiveViewPage {
  /**
   * Factory method for job forms by index
   */
  jobForm(jobIndex: number): JobFormPage {
    return new JobFormPage(this.page, jobIndex);
  }

  /**
   * Factory method for job nodes by name
   */
  jobNode(jobName: string): JobNodePage {
    return new JobNodePage(this.page, jobName);
  }
}

// Usage
test('configure multiple jobs', async ({ page }) => {
  const workflowEdit = new WorkflowEditPage(page);

  await page.goto('/w/123');
  await workflowEdit.waitForConnected();

  // Create different instances
  await workflowEdit.jobForm(0).nameInput.fill('Job 1');
  await workflowEdit.jobForm(1).nameInput.fill('Job 2');

  await workflowEdit.jobNode('Job 1').clickRunButton();
  await workflowEdit.jobNode('Job 2').clickDeleteButton();
});
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

## Testing Multiple Page Variants

### Handling Old and New Implementations

When introducing a new collaborative editor alongside the old LiveView editor:

```typescript
// pages/workflow-edit.page.ts (OLD - LiveView)
export class WorkflowEditPage extends LiveViewPage {
  // ... existing LiveView implementation
}

// pages/workflow-collab.page.ts (NEW - React collaborative)
export class WorkflowCollabPage {
  constructor(protected page: Page) {}

  // New collaborative editor methods
  async waitForYjsConnection(): Promise<void> {
    await this.page.waitForFunction(() => {
      return window.ydoc && window.ydoc.synced;
    });
  }

  async waitForPresenceUpdate(): Promise<void> {
    // Wait for presence indicator
    await this.page.waitForSelector('[data-presence="connected"]');
  }
}
```

**Usage in tests:**
```typescript
test('old workflow editor', async ({ page }) => {
  const workflowEdit = new WorkflowEditPage(page);
  await page.goto('/w/123'); // Old route
  await workflowEdit.waitForConnected();
  // Test old editor
});

test('new collaborative editor', async ({ page }) => {
  const workflowCollab = new WorkflowCollabPage(page);
  await page.goto('/collab/w/123'); // New route
  await workflowCollab.waitForYjsConnection();
  // Test new editor
});
```

### Shared Component POMs

Reuse component POMs across implementations:

```typescript
// Both use same diagram component
export class WorkflowEditPage extends LiveViewPage {
  readonly diagram: WorkflowDiagramPage;

  constructor(page: Page) {
    super(page);
    this.diagram = new WorkflowDiagramPage(page);
  }
}

export class WorkflowCollabPage {
  readonly diagram: WorkflowDiagramPage;

  constructor(page: Page) {
    this.diagram = new WorkflowDiagramPage(page);
  }
}
```

## Index Files

### Exporting Page Objects

Create index files for clean imports:

```typescript
// pages/index.ts
export * from './login.page';
export * from './projects.page';
export * from './workflows.page';
export * from './workflow-edit.page';
export * from './workflow-collab.page';
export * from './components';
export * from './base';

// Usage in tests
import {
  LoginPage,
  ProjectsPage,
  WorkflowEditPage,
  WorkflowCollabPage
} from '../pages';
```

```typescript
// pages/components/index.ts
export * from './workflow-diagram.page';
export * from './job-form.page';
export * from './job-inspector.page';
```

