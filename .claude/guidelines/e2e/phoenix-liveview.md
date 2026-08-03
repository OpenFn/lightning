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

`expectFlashMessage` is defined once, on the base class —
`assets/test/e2e/pages/base/liveview.page.ts:41-46`. Read it there.

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

### Lightning hooks worth knowing

**`Flash`** — flash message containers. This is the one the POM base class uses:
`liveview.page.ts:11` selects `[id^="flash-"][phx-hook="Flash"]`, and
`expectFlashMessage(text)` filters it by text.

**`ReactComponent`** and **`HeexReactComponent`** — the two React mount points.
`ReactComponent` is set from Elixir in `layout_components.ex:374` and `:448`;
`HeexReactComponent` from `react.ex:121`. They are generic: every React island in the app
mounts through one of them, so `[phx-hook="ReactComponent"]` tells you React has mounted
*something*, not which component. Address the component itself, usually via a
`data-testid` it renders.

There is no `Monaco` hook and no `ReactHook` hook. Monaco is mounted from React
(`assets/js/collaborative-editor/components/CollaborativeMonaco.tsx`), not from a
LiveView hook, so there is no `phx-hook` to wait on and no Monaco-specific testid — wait
on `.monaco-editor` instead.

## WebSocket Monitoring

### Listening to WebSocket Events

Register the listener **before** `goto` — a LiveView opens its socket during mount, so a
listener attached afterwards misses the join frames.

```typescript
test('monitor LiveView messages', async ({ page }) => {
  const received: string[] = [];

  page.on('websocket', ws => {
    ws.on('framereceived', frame => received.push(frame.payload as string));
  });

  const workflowsPage = new WorkflowsPage(page);
  await page.goto(`/projects/${projectId}/w`);
  await workflowsPage.waitForConnected();

  await expect
    .poll(() => received.length, { timeout: 5000 })
    .toBeGreaterThan(0);
});
```

This is the only WebSocket-frame example in the guidelines. `collaborative-testing.md`
points here rather than keeping a second copy.

### Identifying a LiveView diff frame

A server-to-client diff carries a `"d"` key in its payload, so `payload.includes('"d":[')`
is enough to tell a diff from a heartbeat or an event reply when you are reading frames.

## Lightning-Specific Patterns

### Sidebar Navigation

`clickMenuItem(text)` is real (`liveview.page.ts:16-21`): it scopes a `getByRole('link')`
to `#side-menu`. It lives on the abstract base, so reach it through a concrete page
object — `ProjectsPage` or `WorkflowsPage`, both of which extend `LiveViewPage`.

```typescript
import { ProjectsPage, WorkflowsPage } from '../pages';

test('navigate sidebar menu', async ({ page }) => {
  const workflowsPage = new WorkflowsPage(page);

  await page.goto(`/projects/${projectId}/w`);
  await workflowsPage.waitForConnected();

  // Each sidebar click crosses LiveViews, so re-wait every time
  await workflowsPage.clickMenuItem('Workflows');
  await workflowsPage.waitForConnected();
});
```

`ProjectsPage.navigateToProjects()` (`projects.page.ts:34-37`) already wraps the
click-plus-re-wait pair for that one destination.

