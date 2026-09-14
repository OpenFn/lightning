# Testing Collaborative Features with Playwright

## Overview

Lightning's collaborative workflow editor uses Yjs CRDTs and Phoenix Channels
for real-time multi-user editing. Testing these features requires simulating
multiple users, monitoring WebSocket connections, and verifying eventual
consistency.

This guide covers patterns for testing collaborative editing, presence
awareness, and conflict resolution.

## Two things that will stop you before you start

**`enableExperimentalFeatures(email)` is a hard precondition, per user.** The
collaborative editor sits behind a per-user flag. `enableExperimentalFeatures()` in
`assets/test/e2e/e2e-helper.ts` sets it, and every collaborative spec calls it before
logging in — see `specs/collaborative/job-step-sync.spec.ts:27`. A two-user test that
enables the flag for one user never reaches the editor as the other.

**`WorkflowCollaborativePage.waitForSynced()` is currently suspect.**
`pages/workflow-collab.page.ts:87-89` waits for the locator `text=Synced` with a 15
second timeout. Nothing in `lib/` renders that string, and nothing in `assets/js/`
renders it either — `isSynced` and `lastSyncTime` are identifiers, and
`VersionDebugLogger.tsx:91` writes "Synced" to the console, not the DOM. `open()`
calls `waitForSynced()`, so five spec files reach it, and no CI job runs Playwright.
Assume the gate does not currently pass and check it before you trust a green or red
result from anything below.

## Multi-user test template

Two browser contexts, each with its own logged-in user. No spec in the suite runs
multiple contexts yet, so this is the shape to follow rather than one to copy from.

```typescript
import { expect, test } from '@playwright/test';
import { enableExperimentalFeatures } from '../../e2e-helper';
import { getTestData } from '../../test-data';
import { LoginPage, WorkflowCollaborativePage } from '../../pages';

test('collaborative feature', async ({ browser }) => {
  const testData = await getTestData();
  const users = [testData.users.editor, testData.users.admin];

  // Per-user flag, before either login
  for (const user of users) {
    await enableExperimentalFeatures(user.email);
  }

  const contexts = await Promise.all([
    browser.newContext(),
    browser.newContext(),
  ]);

  try {
    const seats = await Promise.all(
      contexts.map(async (context, i) => {
        const page = await context.newPage();
        await page.goto('/');
        await new LoginPage(page).loginIfNeeded(
          users[i].email,
          users[i].password
        );

        const editor = new WorkflowCollaborativePage(page);
        await editor.open({
          projectId: testData.projects.openhie.id,
          workflowId: testData.workflows.openhie.id,
        });
        return { page, editor };
      })
    );

    // ... the collaborative assertion
  } finally {
    await Promise.all(contexts.map(context => context.close()));
  }
});
```

Keep the `page` alongside the POM. `LiveViewPage` holds `page` as `protected`, so a test
cannot reach it through the page object.

`test-data.ts:21-35` shapes three seeded accounts — `demo@openfn.org` (admin),
`editor@openfn.org` and `viewer@openfn.org`. They are distinct logins with distinct
roles on the instance. Their role *on a given project* is not visible in
`test-data.ts`, so do not build a permission-asymmetry assertion on them without
checking first.

## Presence: join and leave

`ActiveCollaborators.tsx` is the only presence surface with a DOM hook. It renders one
avatar per **remote** user — `useAwareness()` always excludes the local user
(`hooks/useAwareness.ts:295`) — and returns `null` when there are none
(`ActiveCollaborators.tsx:20-22`). There is no per-user testid; count the avatars.

```typescript
const avatars = (page: Page) =>
  page.locator('[class*="inline-flex"][class*="rounded-full"][class*="border-2"]');

// user 1 alone sees no avatars at all — the component renders null
await expect(avatars(seats[0].page)).toHaveCount(0);

// once user 2 joins, user 1 sees exactly one
await expect(avatars(seats[0].page)).toHaveCount(1);
```

**Leaving is not immediate, and this is the trap in the scenario.**
`ActiveCollaborators.tsx:18` calls `useAwareness({ cached: true })`, which merges users
who have disconnected within `CACHE_TTL` — 60 seconds
(`stores/createAwarenessStore.ts:136`). Closing a context does not drop the count for
up to a minute. What changes sooner is the avatar's border: `:47` switches from
`border-green-500` to `border-gray-500` once `lastSeen` is older than 0.2 minutes.
Assert on the border class for a leave, or give the count assertion a timeout longer
than the TTL.

Presence *identity* costs more than presence count. The name and email live in a Radix
tooltip (`Tooltip.tsx:32-35`), and Radix only mounts portal content while the tooltip
is open, so identifying who is present means hovering each avatar in turn.

## Cursor and selection awareness

`Cursors.tsx:63-85` injects one CSS rule per remote client, keyed by Yjs client ID:
`.yRemoteSelection-${clientId}` and `.yRemoteSelectionHead-${clientId}`. y-monaco puts
elements carrying those classes inside the Monaco editor. The production component
queries them itself at `Cursors.tsx:94-96`, which is the proof that the selector shape
resolves against real DOM:

```typescript
document.querySelectorAll('[class*="yRemoteSelectionHead-"]');
```

Use the same attribute-substring form in tests. The client ID is assigned per
connection, so never hard-code one. Remote carets only appear inside a Monaco instance
(`components/CollaborativeMonaco.tsx`), so the other user has to have a job body open
and a cursor placed in it.

```typescript
// user 1 has placed a cursor in a job body; user 2 sees the remote caret
await expect(
  seats[1].page.locator('.monaco-editor [class*="yRemoteSelectionHead-"]')
).toHaveCount(1);
```

## Concurrent edits and convergence

This is the scenario the file exists for: two users editing the same field and
converging on one value.

Yjs is a YATA CRDT, not last-writer-wins. Concurrent `Y.Map.set` calls on the same key
resolve deterministically in favour of the **higher client ID**, which has nothing to
do with wall-clock order. The state vector is a sync-delta mechanism, not a conflict
arbiter. So assert that both users converge on *one of* the candidate values; never
assert which one.

The job name is the cheapest field to use — one `Y.Map` key, and a real
`input[name="name"]` inside `[data-testid="job-inspector"]`, which
`JobInspectorPage.nameInput` already wraps.

```typescript
const name1 = seats[0].editor.jobInspector.nameInput;
const name2 = seats[1].editor.jobInspector.nameInput;

await Promise.all([
  name1.pressSequentially('User 1 Version'),
  name2.pressSequentially('User 2 Version'),
]);

const value1 = await name1.inputValue();
const value2 = await name2.inputValue();

expect(value1).toBe(value2);
expect(['User 1 Version', 'User 2 Version']).toContain(value1);
```

`pressSequentially` replaces `Locator.type`, which is deprecated. Do not gate
convergence on `waitForTimeout` — wait on an observable signal, or let a web-first
assertion retry.

## Offline and reconnect

Two hooks, and they test different things.

`window.triggerSessionReconnect(timeout)` (`contexts/SessionProvider.tsx:203`) is a
testing helper the editor deliberately exposes: it disconnects the Phoenix socket and
reconnects it after `timeout` ms. It is the only `window.*` global the collaborative
editor defines. Use it to exercise the app's own reconnect path.

`context.setOffline(true)` cuts the browser context's network instead, which is what
you want for edits made while genuinely offline and replayed on reconnect.

```typescript
await page.evaluate(() => window.triggerSessionReconnect(500));
// ... then assert the editor recovers and the edit survived
```

There is no rendered connection-status element to assert against — the state lives in
`ConnectionStatusContext`, nothing consumes `useConnectionStatus()`, and Playwright
cannot address React context. Assert on editor behaviour after reconnect, not on a
status indicator.

## Not covered here

Yjs and Phoenix Channel internals, presence toasts, server-pushed workflow status,
slow-network simulation and sync-latency measurement have no DOM or JavaScript hook in
the components today, so there is nothing to write a test against yet. `window.ydoc`
and `window.workflowChannel` do not exist and never did under another name.

For WebSocket frame monitoring, see
`.claude/guidelines/e2e/phoenix-liveview.md §WebSocket Monitoring`.

> For LiveView-level wait patterns, see `.claude/guidelines/e2e/phoenix-liveview.md §LiveView waits`.
