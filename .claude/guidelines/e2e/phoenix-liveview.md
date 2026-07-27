# Testing Phoenix LiveView with Playwright

## Overview

Phoenix LiveView uses WebSocket connections to provide real-time, server-rendered
interactivity. Testing LiveView applications requires special handling for
connection lifecycle, event handlers, and server-pushed updates.

This guide covers Lightning-specific patterns for testing Phoenix LiveView
components with Playwright.

## LiveView waits

Canonical wait patterns for Phoenix LiveView pages. Other e2e guidelines cross-reference this section for `waitForConnected`, `phx-connected`, and `phx-change` timing rules.

### waitForConnected

Wait for the LiveView connection before interacting with elements on the page.

```typescript
import { LiveViewPage } from '../pages/base';

test('interact with workflow editor', async ({ page }) => {
  const workflowPage = new LiveViewPage(page);

  await page.goto('/workflows/123/edit');

  // Wait for LiveView to connect and mount
  await workflowPage.waitForConnected();

  // Now safe to interact
  await page.getByRole('button', { name: 'Add Job' }).click();
});
```

**Implementation** (canonical — `page-objects.md` cross-refs this):

```typescript
async waitForConnected(): Promise<void> {
  const locator = this.page.locator('[data-phx-main]');
  await expect(locator).toBeVisible();
  await expect(locator).toHaveClass(/phx-connected/);
}
```

### Detecting connection state via liveSocket

```typescript
const isConnected = await page.evaluate(() => {
  return window.liveSocket && window.liveSocket.isConnected();
});
```

### Re-waiting after LiveView navigation

Each LiveView navigation establishes a new WebSocket connection — call `waitForConnected()` again after any link click that crosses LiveViews.

```typescript
await page.getByRole('link', { name: 'openhie-project' }).click();
await workflowPage.waitForConnected(); // new connection, must re-wait
```

## Event Handlers

### Understanding phx-* Attributes

LiveView uses special attributes to bind event handlers:

- `phx-click` - Click events
- `phx-change` - Form input changes
- `phx-submit` - Form submissions
- `phx-blur` - Input blur events
- `phx-focus` - Input focus events
- `phx-keydown`/`phx-keyup` - Keyboard events
- `phx-hook` - JavaScript hook mounting points

### Waiting for Event Handlers

Event handlers may not be immediately attached after navigation:

```typescript
test('wait for handlers before clicking', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  await page.goto('/workflows/new');
  await liveViewPage.waitForConnected();

  const createButton = page.getByRole('button', { name: 'Create' });

  // Wait for phx-click handler to be attached
  await liveViewPage.waitForEventAttached(createButton, 'click');

  // Now safe to click
  await createButton.click();
});
```

## Server-Pushed Updates

### Waiting for Server Updates

LiveView can push updates from server to client. Use web-first assertions to
wait for these updates:

```typescript
test('workflow status updates in real-time', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  await page.goto('/workflows/123');
  await liveViewPage.waitForConnected();

  // Trigger workflow execution
  await page.getByRole('button', { name: 'Run' }).click();

  // Wait for server to push status update
  await expect(page.getByTestId('workflow-status'))
    .toHaveText('Running', { timeout: 10000 });

  // Wait for completion
  await expect(page.getByTestId('workflow-status'))
    .toHaveText('Completed', { timeout: 30000 });
});
```

### Polling with Socket Ping

For critical operations, ensure WebSocket messages are processed:

```typescript
test('save and verify persistence', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  await page.goto('/workflows/123/edit');
  await liveViewPage.waitForConnected();

  // Make changes
  await page.getByLabel('Workflow name').fill('Updated Name');

  // Save
  await page.getByRole('button', { name: 'Save' }).click();

  // Wait for socket to settle (all pending messages processed)
  await liveViewPage.waitForSocketSettled();

  // Verify save was processed
  await expect(page.getByText('Workflow saved')).toBeVisible();
});
```

**What `waitForSocketSettled()` does:**
```typescript
async waitForSocketSettled(): Promise<void> {
  await this.page.waitForFunction(() => {
    return new Promise(resolve => {
      window.liveSocket.socket.ping(resolve);
    });
  });
}
```

## Form Handling

### LiveView Forms with phx-change

LiveView forms trigger events on every change:

```typescript
test('form updates trigger LiveView events', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  await page.goto('/workflows/new');
  await liveViewPage.waitForConnected();

  // Each input change triggers phx-change event
  await page.getByLabel('Workflow name').fill('ETL Pipeline');

  // LiveView may update UI based on validation
  await expect(page.getByText('Name is valid')).toBeVisible();

  // Select dropdown triggers phx-change
  await page.getByLabel('Workflow type').selectOption('event-based');

  // LiveView updates form based on selection
  await expect(page.getByLabel('Trigger type')).toBeVisible();
});
```

### Form Submission

```typescript
test('submit LiveView form', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  await page.goto('/workflows/new');
  await liveViewPage.waitForConnected();

  // Fill form
  await page.getByLabel('Workflow name').fill('Test Workflow');
  await page.getByLabel('Description').fill('Test description');

  // Submit triggers phx-submit
  await page.getByRole('button', { name: 'Create' }).click();

  // LiveView handles submission and redirects/updates
  await expect(page).toHaveURL(/\/w\/[a-f0-9-]+/);
  await expect(page.getByText('Workflow created')).toBeVisible();
});
```

### Debounced Inputs

LiveView often debounces rapid input changes:

```typescript
test('search with debounced input', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  await page.goto('/workflows');
  await liveViewPage.waitForConnected();

  // Type search query
  const searchInput = page.getByPlaceholder('Search workflows...');
  await searchInput.fill('ETL');

  // Wait for debounce (usually 300-500ms in Lightning)
  await page.waitForTimeout(600);

  // Or better: wait for results to appear
  await expect(page.getByText('ETL Pipeline')).toBeVisible();
});
```

## Flash Messages

### Asserting Flash Messages

Lightning uses LiveView flash messages for notifications:

```typescript
test('verify flash message', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  await page.goto('/workflows/123/edit');
  await liveViewPage.waitForConnected();

  await page.getByRole('button', { name: 'Save' }).click();

  // Flash message appears via LiveView push
  await liveViewPage.expectFlashMessage('Workflow saved successfully.');
});
```

**What `expectFlashMessage()` does:**
```typescript
async expectFlashMessage(text: string): Promise<void> {
  const flashMessage = this.page
    .locator('[id^="flash-"][phx-hook="Flash"]')
    .filter({ hasText: text });

  await expect(flashMessage).toBeVisible();
}
```

### Flash Message Lifecycle

Flash messages auto-dismiss after a timeout:

```typescript
test('flash message disappears', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  await page.goto('/workflows/123/edit');
  await liveViewPage.waitForConnected();

  await page.getByRole('button', { name: 'Save' }).click();

  // Flash appears
  const flash = page.locator('[id^="flash-"]');
  await expect(flash).toBeVisible();

  // Flash auto-dismisses (usually 5 seconds)
  await expect(flash).not.toBeVisible({ timeout: 10000 });
});
```

## LiveView Hooks

### Testing JavaScript Hooks

LiveView hooks provide custom client-side behavior:

```typescript
test('Monaco editor hook initializes', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  await page.goto('/workflows/123/edit');
  await liveViewPage.waitForConnected();

  // Element with phx-hook="Monaco"
  const editorElement = page.locator('[phx-hook="Monaco"]');

  // Wait for hook to mount and initialize
  await expect(editorElement).toBeVisible();

  // Wait for Monaco editor to be ready
  await page.waitForFunction(() => {
    const element = document.querySelector('[phx-hook="Monaco"]');
    return element && (element as any).monacoEditor !== undefined;
  });

  // Now safe to interact with editor
  await page.keyboard.type('console.log("Hello");');
});
```

### Common Lightning Hooks

**Flash Hook**: Auto-dismissing notifications
```typescript
// Located on flash message elements
const flash = page.locator('[phx-hook="Flash"]');
```

**Monaco Hook**: Code editor initialization
```typescript
// Located on code editor containers
const editor = page.locator('[phx-hook="Monaco"]');
```

**ReactHook**: React component mounting points
```typescript
// Located where React components mount
const reactComponent = page.locator('[phx-hook="ReactHook"]');
```

## WebSocket Monitoring

### Listening to WebSocket Events

```typescript
test('monitor LiveView messages', async ({ page }) => {
  const messages: string[] = [];

  // Listen to WebSocket
  page.on('websocket', ws => {
    console.log(`WebSocket connected: ${ws.url()}`);

    ws.on('framereceived', frame => {
      const payload = frame.payload;
      console.log('Received:', payload);
      messages.push(payload);
    });

    ws.on('framesent', frame => {
      console.log('Sent:', frame.payload);
    });
  });

  await page.goto('/workflows/123/edit');

  // Make changes that trigger WebSocket messages
  await page.getByLabel('Workflow name').fill('Updated');

  // Wait for messages
  await page.waitForTimeout(1000);

  // Verify messages were sent/received
  expect(messages.length).toBeGreaterThan(0);
});
```

### Verifying Specific Messages

```typescript
test('verify LiveView diff message', async ({ page }) => {
  const diffReceived = new Promise<boolean>((resolve) => {
    page.on('websocket', ws => {
      ws.on('framereceived', frame => {
        const payload = frame.payload;
        // LiveView diffs contain "d" (diff) key
        if (payload.includes('"d":[')) {
          resolve(true);
        }
      });
    });
  });

  await page.goto('/workflows');

  // Trigger action that causes server diff
  await page.getByRole('button', { name: 'Refresh' }).click();

  // Verify diff was received
  expect(await Promise.race([
    diffReceived,
    new Promise(resolve => setTimeout(() => resolve(false), 5000))
  ])).toBe(true);
});
```

## Lightning-Specific Patterns

### Workflow Editor (LiveView)

```typescript
import { WorkflowEditPage } from '../pages';

test('interact with workflow editor', async ({ page }) => {
  const workflowEdit = new WorkflowEditPage(page);

  await page.goto('/w/123');
  await workflowEdit.waitForConnected();
  await page.waitForLoadState('networkidle');

  // Use workflow-specific methods
  await workflowEdit.setWorkflowName('Updated');
  await workflowEdit.diagram.clickNode('Job 1');
  await workflowEdit.clickSaveWorkflow();

  await workflowEdit.expectFlashMessage('Workflow saved');
});
```

### Sidebar Navigation

```typescript
test('navigate sidebar menu', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  await page.goto('/projects/123/w');
  await liveViewPage.waitForConnected();

  // Sidebar menu items
  await liveViewPage.clickMenuItem('Workflows');
  await liveViewPage.waitForConnected();

  await liveViewPage.clickMenuItem('Settings');
  await liveViewPage.waitForConnected();
});
```

