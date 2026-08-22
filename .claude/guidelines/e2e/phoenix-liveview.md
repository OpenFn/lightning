# Testing Phoenix LiveView with Playwright

Lightning-specific patterns for driving Phoenix LiveView pages from Playwright.

## LiveView waits

Canonical wait patterns for Phoenix LiveView pages. Other e2e guidelines cross-reference this section for `waitForConnected`, `phx-connected`, and `phx-change` timing rules.

### waitForConnected

Wait for the LiveView connection before interacting with elements on the page.
`LiveViewPage` is `abstract`, so instantiate a concrete subclass — `ProjectsPage`,
`WorkflowsPage`, `LoginPage` or `WorkflowCollaborativePage`.

```typescript
import { WorkflowsPage } from '../pages';

test('workflow list is interactive', async ({ page }) => {
  const workflowsPage = new WorkflowsPage(page);

  await page.goto(`/projects/${projectId}/w`);

  // Wait for LiveView to connect and mount
  await workflowsPage.waitForConnected();

  await workflowsPage.navigateToWorkflow(testData.workflows.openhie.name);
});
```

`WorkflowCollaborativePage.open({ projectId, workflowId })` is the entry point for the
collaborative editor. It navigates to `/projects/:projectId/w/:workflowId`, waits for
`[data-testid="collaborative-editor"]` plus `networkidle`, then calls `waitForSynced()`.
Do **not** treat that last step as a working sync gate: `waitForSynced()` matches
`text=Synced`, which nothing renders. See
`.claude/guidelines/e2e/collaborative-testing.md §Two things that will stop you before you
start`.

`waitForConnected` is defined once, on the base class —
`assets/test/e2e/pages/base/liveview.page.ts:31-35`. It waits for `div[data-phx-main]` to
be visible and to carry the class `phx-connected`. Read the implementation there rather
than from a copy: the two copies that used to sit in these guidelines had both drifted the
same way, writing `toHaveClass` where the source says `toContainClass`.

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

### Waiting for Event Handlers

Event handlers may not be attached immediately after navigation.
`waitForEventAttached(locator, eventType, timeout)` is real —
`liveview.page.ts:74-103` — and for `'click'` it checks that the element carries
`phx-click` and that `[data-phx-main]` has `phx-connected`.

```typescript
import { WorkflowsPage } from '../pages';

test('wait for handlers before clicking', async ({ page }) => {
  const workflowsPage = new WorkflowsPage(page);

  await page.goto(`/projects/${projectId}/w`);
  await workflowsPage.waitForConnected();

  const createButton = page.getByRole('button', {
    name: 'Create new workflow',
  });
  await workflowsPage.waitForEventAttached(createButton, 'click');
  await createButton.click();
});
```

`WorkflowsPage.clickNewWorkflow()` (`workflows.page.ts:21-35`) already does exactly this
sequence, and is what a test should normally call.

## Server-Pushed Updates

### Waiting for Server Updates

LiveView pushes updates from server to client. Use web-first assertions with a generous
timeout — they retry until the push lands, so no explicit wait is needed.

For a worked example, read `assets/test/e2e/specs/collaborative/job-step-sync.spec.ts`: a
real end-to-end server-push test on a real route with real assertions. The `beforeAll` /
`getTestData()` shape it uses is written out in
`.claude/guidelines/e2e-testing.md §Test Data Management`.

### Polling with Socket Ping

`waitForSocketSettled()` pings the LiveView socket and resolves on the reply, as a way of
letting pending messages drain before you assert.

**Treat it as unproven.** Its own docstring says so: *"This _hopefully_ ensures that any
pending messages have been processed. NOTE: still needs to be verified."* A `ping` reply
tells you the socket is responsive; it does not prove an earlier `phx-submit` has been
handled. Prefer asserting on the effect you actually care about, and reach for this only
when there is no observable effect to wait on.

```typescript
const workflowsPage = new WorkflowsPage(page);

await page.goto(`/projects/${projectId}/w`);
await workflowsPage.waitForConnected();

// ... the action under test

await workflowsPage.waitForSocketSettled();
```

`waitForSocketSettled` is defined once, on the base class —
`assets/test/e2e/pages/base/liveview.page.ts:55-61`. Read it there.

## Form Handling

### Debounced Inputs

LiveView debounces some inputs, so the server response lags the keystroke. Wait on the
result, never on the clock: a web-first assertion such as
`await expect(page.getByText('ETL Pipeline')).toBeVisible()` retries until the debounced
round trip lands.

**No fixed sleeps.** `page.waitForTimeout()` does not belong in a passing test — it either
hides a missing wait or wastes the interval. There is no exception for CRDT convergence;
`expect.poll` and web-first assertions cover it. The suite currently has 26
`waitForTimeout` calls across its spec files, which is a debt to work down, not a pattern
to copy.

## Flash Messages

### Asserting Flash Messages

Lightning uses LiveView flash messages for notifications. `expectFlashMessage` is on the
base class, so call it through a concrete page object — `LiveViewPage` is `abstract` and
cannot be instantiated.

```typescript
import { ProjectsPage } from '../pages';

test('verify flash message', async ({ page }) => {
  const projectsPage = new ProjectsPage(page);

  await page.goto('/');
  await projectsPage.waitForConnected();

  // ... the action under test

  await projectsPage.expectFlashMessage('<the exact flash text the action pushes>');
});
```

The match is a `hasText` filter, so pass text that really appears — read it off the
`put_flash` call in the LiveView rather than guessing.

Most feedback inside the React collaborative editor is a toast, not a LiveView flash, so
`expectFlashMessage` is usually the wrong assertion there. The hosting LiveView does push
one flash — the authorization error at
`lib/lightning_web/live/workflow_live/collaborate.ex:57`.

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

