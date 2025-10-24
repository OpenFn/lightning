# Testing Phoenix LiveView with Playwright

## Overview

Phoenix LiveView uses WebSocket connections to provide real-time, server-rendered
interactivity. Testing LiveView applications requires special handling for
connection lifecycle, event handlers, and server-pushed updates.

This guide covers Lightning-specific patterns for testing Phoenix LiveView
components with Playwright.

## LiveView Connection Lifecycle

### Understanding the Connection Flow

```
User navigates to page
        ↓
HTML renders (static)
        ↓
LiveView JavaScript loads
        ↓
WebSocket connects to Phoenix
        ↓
LiveView "mounts" on server
        ↓
Server sends initial state
        ↓
DOM updated with phx-connected class
        ↓
Event handlers attached
        ↓
Page ready for interaction
```

### Waiting for LiveView Connection

**Always wait for connection before interacting with LiveView elements.**

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

**What `waitForConnected()` does:**
```typescript
async waitForConnected(): Promise<void> {
  const locator = this.page.locator('[data-phx-main]');
  await expect(locator).toBeVisible();
  await expect(locator).toHaveClass(/phx-connected/);
}
```

### Detecting Connection State

```typescript
test('verify LiveView connection', async ({ page }) => {
  await page.goto('/workflows');

  // Check if LiveView is connected
  const isConnected = await page.evaluate(() => {
    return window.liveSocket && window.liveSocket.isConnected();
  });

  expect(isConnected).toBe(true);
});
```

### Handling Connection Transitions

When navigating between LiveView pages, a new WebSocket connection is
established:

```typescript
test('navigate between LiveView pages', async ({ page }) => {
  const workflowPage = new LiveViewPage(page);

  // First page load
  await page.goto('/projects');
  await workflowPage.waitForConnected();

  // Click link to new LiveView page
  await page.getByRole('link', { name: 'openhie-project' }).click();

  // IMPORTANT: Wait for new connection
  await workflowPage.waitForConnected();

  // Now safe to interact with new page
  await page.getByRole('link', { name: 'Workflows' }).click();
});
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

### Handling Race Conditions

**Problem**: Clicking elements before LiveView attaches handlers:

```typescript
// ❌ BAD: May click before handler is attached
test('create workflow - FLAKY', async ({ page }) => {
  await page.goto('/workflows/new');

  // Race condition: LiveView might not be connected yet
  await page.getByRole('button', { name: 'Create' }).click();

  // Handler not attached - click does nothing!
});
```

**Solution**: Wait for connection and network idle:

```typescript
// ✅ GOOD: Wait for full initialization
test('create workflow - STABLE', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  await page.goto('/workflows/new');

  // Wait for LiveView connection
  await liveViewPage.waitForConnected();

  // Wait for any pending async operations
  await page.waitForLoadState('networkidle');

  // Now safe to click
  await page.getByRole('button', { name: 'Create' }).click();
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

## Common Patterns

### Navigate and Wait Pattern

Standard pattern for all LiveView navigation:

```typescript
test('navigate to workflow', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  // 1. Navigate
  await page.goto('/projects/123/w');

  // 2. Wait for LiveView connection
  await liveViewPage.waitForConnected();

  // 3. Optionally wait for network idle
  await page.waitForLoadState('networkidle');

  // 4. Now safe to interact
  await page.getByRole('link', { name: 'OpenHIE Workflow' }).click();

  // 5. Wait for new LiveView connection after navigation
  await liveViewPage.waitForConnected();
});
```

### Form Interaction Pattern

```typescript
test('fill and submit form', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  await page.goto('/workflows/new');
  await liveViewPage.waitForConnected();

  // Fill form (each change triggers phx-change)
  await page.getByLabel('Name').fill('Test');
  await page.getByLabel('Type').selectOption('event-based');

  // Wait for validation
  await expect(page.getByText('Valid')).toBeVisible();

  // Submit (triggers phx-submit)
  await page.getByRole('button', { name: 'Create' }).click();

  // Wait for socket to process submission
  await liveViewPage.waitForSocketSettled();

  // Verify result
  await expect(page.getByText('Created')).toBeVisible();
});
```

### Real-Time Update Pattern

```typescript
test('wait for real-time updates', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  await page.goto('/workflows/123/runs');
  await liveViewPage.waitForConnected();

  // Trigger action that causes server updates
  await page.getByRole('button', { name: 'Start Run' }).click();

  // Wait for status to update via LiveView push
  await expect(page.getByTestId('run-status'))
    .toHaveText('Running', { timeout: 10000 });

  // Wait for completion
  await expect(page.getByTestId('run-status'))
    .toHaveText('Completed', { timeout: 60000 });
});
```

## Troubleshooting

### Test Clicks Don't Work

**Symptom**: Clicking buttons/links has no effect

**Cause**: Event handlers not attached yet

**Solution**:
```typescript
test('fix missing handlers', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  await page.goto('/workflows/new');

  // Add these waits
  await liveViewPage.waitForConnected();
  await page.waitForLoadState('networkidle');

  // Now clicks work
  await page.click('text=Create');
});
```

### Form Changes Don't Trigger Updates

**Symptom**: Typing in input doesn't update UI

**Cause**: LiveView not connected or phx-change handler missing

**Solution**:
```typescript
test('fix form updates', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  await page.goto('/form');
  await liveViewPage.waitForConnected();

  // Verify phx-change is present
  const form = page.locator('form');
  await expect(form).toHaveAttribute('phx-change');

  // Now inputs work
  await page.fill('input[name="name"]', 'Test');
});
```

### Flash Messages Don't Appear

**Symptom**: Expected flash message never appears

**Cause**: Socket not settled before assertion

**Solution**:
```typescript
test('fix flash messages', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  await page.goto('/workflows/123/edit');
  await liveViewPage.waitForConnected();

  await page.click('text=Save');

  // Add socket settle wait
  await liveViewPage.waitForSocketSettled();

  // Now flash appears reliably
  await liveViewPage.expectFlashMessage('Saved');
});
```

### Tests Fail After Navigation

**Symptom**: Tests work initially but fail after clicking links

**Cause**: New LiveView connection not established

**Solution**:
```typescript
test('fix navigation failures', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  await page.goto('/projects');
  await liveViewPage.waitForConnected();

  await page.click('text=OpenHIE Project');

  // ADD THIS: Wait for new connection
  await liveViewPage.waitForConnected();

  // Now interactions work
  await page.click('text=Workflows');
});
```

### Intermittent Failures

**Symptom**: Tests pass sometimes, fail others

**Cause**: Race conditions between test and LiveView

**Solution**:
```typescript
test('fix flaky test', async ({ page }) => {
  const liveViewPage = new LiveViewPage(page);

  await page.goto('/workflows');
  await liveViewPage.waitForConnected();

  // Add comprehensive waits
  await page.waitForLoadState('networkidle');

  // Use web-first assertions (auto-retry)
  await expect(page.getByText('Workflows')).toBeVisible();

  // Wait for socket to settle before critical operations
  await liveViewPage.waitForSocketSettled();

  await page.click('text=New Workflow');
});
```

## Best Practices

### ✅ DO

- **Always wait for connection** using `waitForConnected()`
- **Use web-first assertions** that auto-retry
- **Wait for networkidle** after navigation to new LiveView
- **Wait for socket to settle** before critical assertions
- **Monitor WebSocket** for debugging real-time issues
- **Verify phx-* attributes** are present on interactive elements
- **Use semantic locators** over CSS selectors
- **Test from user perspective** - what they see and do

### ❌ DON'T

- **Don't click immediately** after page load
- **Don't use fixed timeouts** - use proper waiting strategies
- **Don't assume instant updates** - LiveView has network latency
- **Don't test during connection** - wait for phx-connected class
- **Don't ignore WebSocket errors** - they indicate real issues
- **Don't skip networkidle wait** for complex LiveView pages
- **Don't forget re-connection** when navigating between LiveViews

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

---

**Remember**: Phoenix LiveView requires special handling for WebSocket
connections and event handlers. Always wait for connection, use web-first
assertions, and monitor the socket for real-time updates. The `LiveViewPage`
base class provides utilities to make this easier.
