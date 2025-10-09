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
   * Wait for Phoenix LiveView connection
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

## Locator Strategies

### Initialize Locators in Constructor

**❌ BAD: Create locators in methods**
```typescript
class WorkflowEditPage extends LiveViewPage {
  async clickSaveButton() {
    // Creates new locator every time
    await this.page.getByRole('button', { name: 'Save' }).click();
  }
}
```

**✅ GOOD: Initialize in constructor or as properties**
```typescript
class WorkflowEditPage extends LiveViewPage {
  readonly saveButton: Locator;

  constructor(page: Page) {
    super(page);
    // Locator created once
    this.saveButton = page.getByRole('button', { name: 'Save' });
  }

  async clickSaveButton() {
    await this.saveButton.click();
  }
}
```

### Selector Organization

Store selectors in `protected selectors` object:

```typescript
class WorkflowEditPage extends LiveViewPage {
  protected selectors = {
    // Group related selectors
    topBar: {
      container: '[data-testid="top-bar"]',
      saveButton: 'button:has-text("Save")',
      runButton: '[data-testid="run-workflow-btn"]',
    },
    form: {
      nameInput: 'input[name="workflow[name]"]',
      descriptionTextarea: 'textarea[name="workflow[description]"]',
    },
    diagram: {
      canvas: '[data-testid="workflow-canvas"]',
      nodes: '.react-flow__node',
    },
  };

  async clickSaveButton(): Promise<void> {
    const topBar = this.page.locator(this.selectors.topBar.container);
    const saveButton = topBar.locator(this.selectors.topBar.saveButton);
    await saveButton.click();
  }
}
```

## Method Patterns

### Action Methods

Methods that perform user actions:

```typescript
class WorkflowEditPage extends LiveViewPage {
  /**
   * Action methods should:
   * - Be async
   * - Return Promise<void>
   * - Use descriptive verb names
   * - Handle waiting internally
   */

  async clickSaveWorkflow(): Promise<void> {
    await this.page.getByRole('button', { name: 'Save' }).click();
  }

  async setWorkflowName(name: string): Promise<void> {
    const input = this.page.getByLabel('Workflow name');
    await input.fill(name);
  }

  async selectWorkflowType(typeText: string): Promise<void> {
    const label = this.page.locator('label').filter({ hasText: typeText });
    await label.click();
  }
}
```

### Assertion Methods

Methods that verify state:

```typescript
class WorkflowEditPage extends LiveViewPage {
  /**
   * Assertion methods should:
   * - Start with 'verify' or 'expect'
   * - Be async
   * - Contain assertions internally
   */

  async verifyWorkflowSaved(): Promise<void> {
    await this.expectFlashMessage('Workflow saved successfully');
    await expect(this.unsavedChangesIndicator()).not.toBeVisible();
  }

  async verifyUnsavedChanges(): Promise<void> {
    await expect(this.unsavedChangesIndicator()).toBeVisible();
  }
}
```

### Locator Getters

Return locators for flexible assertions:

```typescript
class WorkflowEditPage extends LiveViewPage {
  /**
   * Getter methods should:
   * - Return Locator
   * - Not be async
   * - Allow tests to perform custom assertions
   */

  unsavedChangesIndicator(): Locator {
    return this.page.locator('.unsaved-indicator');
  }

  get workflowNameInput(): Locator {
    return this.page.getByLabel('Workflow name');
  }

  getJobNode(jobName: string): Locator {
    return this.page.locator('.job-node').filter({ hasText: jobName });
  }
}
```

**Usage:**
```typescript
test('verify state', async ({ page }) => {
  const workflowEdit = new WorkflowEditPage(page);

  // Custom assertions on returned locators
  await expect(workflowEdit.workflowNameInput).toHaveValue('ETL Pipeline');
  await expect(workflowEdit.unsavedChangesIndicator()).toBeVisible();
  await expect(workflowEdit.getJobNode('Job 1')).toHaveClass('selected');
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

## Handling Dynamic Content

### Dynamic Selectors

```typescript
class WorkflowsPage extends LiveViewPage {
  /**
   * Navigate to workflow by name (dynamic)
   */
  async navigateToWorkflow(workflowName: string): Promise<void> {
    await this.page
      .getByRole('link', { name: workflowName })
      .click();
  }

  /**
   * Get workflow card by name
   */
  getWorkflowCard(workflowName: string): Locator {
    return this.page
      .locator('.workflow-card')
      .filter({ hasText: workflowName });
  }

  /**
   * Verify workflow is visible
   */
  async verifyWorkflowVisible(workflowName: string): Promise<void> {
    await expect(this.getWorkflowCard(workflowName)).toBeVisible();
  }
}
```

### Indexed Elements

```typescript
class WorkflowDiagramPage extends LiveViewPage {
  /**
   * Get job node by index
   */
  getJobNodeByIndex(index: number): Locator {
    return this.page.locator('.job-node').nth(index);
  }

  /**
   * Click job node by index
   */
  async clickJobNodeByIndex(index: number): Promise<void> {
    const node = this.getJobNodeByIndex(index);
    await expect(node).toBeVisible();
    await node.click();
  }
}
```

## Waiting Strategies

### Built-in Waiting

POM methods should handle waiting internally:

```typescript
class WorkflowEditPage extends LiveViewPage {
  /**
   * ✅ GOOD: Handles waiting internally
   */
  async clickSaveWorkflow(): Promise<void> {
    const saveButton = this.page.getByRole('button', { name: 'Save' });
    // Playwright auto-waits for button to be actionable
    await saveButton.click();
    // Wait for save confirmation
    await this.expectFlashMessage('Workflow saved');
  }

  /**
   * ❌ BAD: Requires caller to wait
   */
  async clickSaveWorkflowBad(): Promise<void> {
    // Caller must ensure button is ready
    await this.page.click('text=Save');
    // No confirmation - caller must check
  }
}
```

### LiveView-Specific Waiting

```typescript
class WorkflowEditPage extends LiveViewPage {
  /**
   * Override goto to include LiveView wait
   */
  async goto(workflowId: string): Promise<void> {
    await this.page.goto(`/w/${workflowId}`);
    await this.waitForConnected();
    await this.page.waitForLoadState('networkidle');
  }

  /**
   * Wait for specific LiveView updates
   */
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

## Best Practices

### ✅ DO

- **Extend LiveViewPage** for Phoenix LiveView pages
- **Initialize locators in constructor** for performance
- **Use semantic locators** (role, label, text) over CSS
- **Handle waiting internally** in POM methods
- **Return Locator** for flexible assertions
- **Compose components** for reusable UI elements
- **Use factory methods** for parameterized components
- **Provide high-level methods** that match user actions
- **Include JSDoc comments** for public methods
- **Group related selectors** in selector objects

### ❌ DON'T

- **Don't put assertions in actions** - separate action and verify methods
- **Don't use CSS selectors** when semantic locators work
- **Don't create locators in methods** - initialize once
- **Don't make tests do the waiting** - POMs should handle it
- **Don't mix concerns** - keep page-specific logic in POMs
- **Don't return promises from getters** - use getters for locators only
- **Don't hardcode test data** - use parameters
- **Don't test in POMs** - POMs enable testing, don't contain tests
- **Don't extend when you can compose** - prefer composition
- **Don't forget to export** from index files

## Common Patterns

### Navigation Pattern

```typescript
class ProjectsPage extends LiveViewPage {
  async navigateToProject(projectName: string): Promise<void> {
    await this.page.getByRole('link', { name: projectName }).click();
    await this.waitForConnected();
  }
}
```

### Form Fill Pattern

```typescript
class WorkflowEditPage extends LiveViewPage {
  async fillWorkflowForm(data: {
    name: string;
    description?: string;
  }): Promise<void> {
    await this.page.getByLabel('Name').fill(data.name);

    if (data.description) {
      await this.page.getByLabel('Description').fill(data.description);
    }
  }
}
```

### Verification Pattern

```typescript
class WorkflowEditPage extends LiveViewPage {
  async verifyWorkflowState(expected: {
    saved: boolean;
    nodeCount: number;
  }): Promise<void> {
    if (expected.saved) {
      await expect(this.unsavedChangesIndicator()).not.toBeVisible();
    }

    await this.diagram.verifyNodeCount(expected.nodeCount);
  }
}
```

---

**Remember**: Page Object Models encapsulate UI structure and interactions.
Keep POMs focused on "how" to interact with the page, while tests focus on
"what" to test. Well-designed POMs make tests readable and maintainable.
