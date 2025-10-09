# Testing Collaborative Features with Playwright

## Overview

Lightning's collaborative workflow editor uses Yjs CRDTs and Phoenix Channels
for real-time multi-user editing. Testing these features requires simulating
multiple users, monitoring WebSocket connections, and verifying eventual
consistency.

This guide covers patterns for testing collaborative editing, presence
awareness, and conflict resolution.

## Multi-User Test Setup

### Creating Multiple Browser Contexts

Simulate multiple users with separate browser contexts:

```typescript
test('multiple users can edit simultaneously', async ({ browser }) => {
  // Create isolated contexts for each user
  const user1Context = await browser.newContext({
    storageState: 'user1-auth.json'
  });
  const user2Context = await browser.newContext({
    storageState: 'user2-auth.json'
  });

  const user1Page = await user1Context.newPage();
  const user2Page = await user2Context.newPage();

  try {
    // Both users navigate to same workflow
    await Promise.all([
      user1Page.goto('/collab/w/123'),
      user2Page.goto('/collab/w/123'),
    ]);

    // Wait for both to connect
    await user1Page.waitForFunction(() => window.ydoc?.synced);
    await user2Page.waitForFunction(() => window.ydoc?.synced);

    // Test collaborative interactions
    await user1Page.getByTestId('job-name-input').fill('User 1 Change');

    // User 2 should see the change via Yjs sync
    await expect(user2Page.getByTestId('job-name-input'))
      .toHaveValue('User 1 Change', { timeout: 5000 });

  } finally {
    await user1Context.close();
    await user2Context.close();
  }
});
```

### Authentication Fixtures

Create authentication states for different users:

```typescript
// global.setup.ts
import { test as setup, expect } from '@playwright/test';

setup('authenticate users', async ({ browser }) => {
  // User 1
  const user1Context = await browser.newContext();
  const user1Page = await user1Context.newPage();
  await user1Page.goto('/login');
  await user1Page.fill('[name="email"]', 'editor@example.com');
  await user1Page.fill('[name="password"]', 'password');
  await user1Page.click('button[type="submit"]');
  await user1Page.waitForURL('/projects');
  await user1Context.storageState({ path: 'user1-auth.json' });
  await user1Context.close();

  // User 2
  const user2Context = await browser.newContext();
  const user2Page = await user2Context.newPage();
  await user2Page.goto('/login');
  await user2Page.fill('[name="email"]', 'viewer@example.com');
  await user2Page.fill('[name="password"]', 'password');
  await user2Page.click('button[type="submit"]');
  await user2Page.waitForURL('/projects');
  await user2Context.storageState({ path: 'user2-auth.json' });
  await user2Context.close();
});
```

## Yjs and Y-Phoenix-Channel Testing

### Waiting for Yjs Connection

```typescript
test('wait for Yjs to sync', async ({ page }) => {
  await page.goto('/collab/w/123');

  // Wait for Y.Doc to be created and synced
  await page.waitForFunction(() => {
    return window.ydoc && window.ydoc.synced === true;
  });

  // Now safe to interact with collaborative editor
  await page.getByTestId('job-name-input').fill('Test Job');
});
```

### Monitoring Yjs Updates

```typescript
test('verify Yjs updates', async ({ page }) => {
  const updates: any[] = [];

  // Listen to Yjs update events
  await page.exposeFunction('captureUpdate', (update: any) => {
    updates.push(update);
  });

  await page.evaluate(() => {
    if (window.ydoc) {
      window.ydoc.on('update', (update: Uint8Array) => {
        (window as any).captureUpdate({ update: Array.from(update) });
      });
    }
  });

  await page.goto('/collab/w/123');

  // Make changes
  await page.getByTestId('job-name-input').fill('Updated Name');

  // Wait for update
  await page.waitForTimeout(1000);

  // Verify updates were sent
  expect(updates.length).toBeGreaterThan(0);
});
```

### Verifying Y.Doc State

```typescript
test('verify Y.Doc contains expected data', async ({ page }) => {
  await page.goto('/collab/w/123');
  await page.waitForFunction(() => window.ydoc?.synced);

  // Get workflow data from Y.Doc
  const workflowData = await page.evaluate(() => {
    if (!window.ydoc) return null;

    const workflow = window.ydoc.getMap('workflow');
    const jobs = workflow.get('jobs');

    return {
      name: workflow.get('name'),
      jobCount: jobs?.length || 0,
      firstJob: jobs?.[0] || null,
    };
  });

  expect(workflowData?.name).toBe('ETL Pipeline');
  expect(workflowData?.jobCount).toBe(3);
  expect(workflowData?.firstJob?.name).toBe('Fetch Data');
});
```

## Phoenix Channel Testing

### Monitoring Channel Messages

```typescript
test('monitor Phoenix Channel messages', async ({ page }) => {
  const messages: string[] = [];

  // Listen to WebSocket frames
  page.on('websocket', ws => {
    console.log(`WebSocket opened: ${ws.url()}`);

    ws.on('framereceived', frame => {
      const payload = frame.payload;
      console.log('Received:', payload);
      messages.push(payload);
    });

    ws.on('framesent', frame => {
      console.log('Sent:', frame.payload);
    });
  });

  await page.goto('/collab/w/123');
  await page.waitForFunction(() => window.ydoc?.synced);

  // Make changes that trigger channel messages
  await page.getByTestId('job-name-input').fill('Updated Job');

  // Wait for messages
  await page.waitForTimeout(1000);

  // Verify Yjs sync messages were sent
  const hasSyncMessage = messages.some(msg =>
    msg.includes('y-sync') || msg.includes('awareness')
  );
  expect(hasSyncMessage).toBe(true);
});
```

### Verifying Channel Connection

```typescript
test('verify Phoenix Channel connection', async ({ page }) => {
  await page.goto('/collab/w/123');

  // Wait for channel to connect
  const channelState = await page.waitForFunction(() => {
    // Access Phoenix Channel state via window
    const channel = (window as any).workflowChannel;
    return channel?.state === 'joined';
  });

  expect(channelState).toBeTruthy();
});
```

## Presence Testing

### Verifying User Presence

Test that users see each other in the collaborative session:

```typescript
test('users see each other in presence', async ({ browser }) => {
  const user1Context = await browser.newContext({
    storageState: 'user1-auth.json'
  });
  const user2Context = await browser.newContext({
    storageState: 'user2-auth.json'
  });

  const user1Page = await user1Context.newPage();
  const user2Page = await user2Context.newPage();

  try {
    // User 1 joins
    await user1Page.goto('/collab/w/123');
    await user1Page.waitForFunction(() => window.ydoc?.synced);

    // User 1 should see themselves
    await expect(user1Page.getByTestId('presence-user-1')).toBeVisible();

    // User 2 joins
    await user2Page.goto('/collab/w/123');
    await user2Page.waitForFunction(() => window.ydoc?.synced);

    // User 1 should see User 2 appear
    await expect(user1Page.getByTestId('presence-user-2'))
      .toBeVisible({ timeout: 5000 });

    // User 2 should see both users
    await expect(user2Page.getByTestId('presence-user-1')).toBeVisible();
    await expect(user2Page.getByTestId('presence-user-2')).toBeVisible();

  } finally {
    await user1Context.close();
    await user2Context.close();
  }
});
```

### Presence Leave Events

```typescript
test('user leaves presence when disconnecting', async ({ browser }) => {
  const user1Context = await browser.newContext({
    storageState: 'user1-auth.json'
  });
  const user2Context = await browser.newContext({
    storageState: 'user2-auth.json'
  });

  const user1Page = await user1Context.newPage();
  const user2Page = await user2Context.newPage();

  try {
    // Both users join
    await Promise.all([
      user1Page.goto('/collab/w/123'),
      user2Page.goto('/collab/w/123'),
    ]);

    await Promise.all([
      user1Page.waitForFunction(() => window.ydoc?.synced),
      user2Page.waitForFunction(() => window.ydoc?.synced),
    ]);

    // Verify both users visible
    await expect(user1Page.getByTestId('presence-user-2'))
      .toBeVisible({ timeout: 5000 });

    // User 2 leaves
    await user2Context.close();

    // User 1 should see User 2 disappear
    await expect(user1Page.getByTestId('presence-user-2'))
      .not.toBeVisible({ timeout: 5000 });

  } finally {
    await user1Context.close();
  }
});
```

### Cursor/Selection Awareness

```typescript
test('users see each others cursors', async ({ browser }) => {
  const user1Context = await browser.newContext({
    storageState: 'user1-auth.json'
  });
  const user2Context = await browser.newContext({
    storageState: 'user2-auth.json'
  });

  const user1Page = await user1Context.newPage();
  const user2Page = await user2Context.newPage();

  try {
    await Promise.all([
      user1Page.goto('/collab/w/123'),
      user2Page.goto('/collab/w/123'),
    ]);

    await Promise.all([
      user1Page.waitForFunction(() => window.ydoc?.synced),
      user2Page.waitForFunction(() => window.ydoc?.synced),
    ]);

    // User 1 focuses on job name input
    await user1Page.getByTestId('job-name-input').click();

    // User 2 should see User 1's cursor indicator
    await expect(user2Page.locator('[data-cursor="user-1"]'))
      .toBeVisible({ timeout: 5000 });

  } finally {
    await user1Context.close();
    await user2Context.close();
  }
});
```

## Concurrent Editing

### Simultaneous Text Edits

```typescript
test('concurrent text edits are merged', async ({ browser }) => {
  const user1Context = await browser.newContext({
    storageState: 'user1-auth.json'
  });
  const user2Context = await browser.newContext({
    storageState: 'user2-auth.json'
  });

  const user1Page = await user1Context.newPage();
  const user2Page = await user2Context.newPage();

  try {
    await Promise.all([
      user1Page.goto('/collab/w/123'),
      user2Page.goto('/collab/w/123'),
    ]);

    await Promise.all([
      user1Page.waitForFunction(() => window.ydoc?.synced),
      user2Page.waitForFunction(() => window.ydoc?.synced),
    ]);

    const jobNameInput1 = user1Page.getByTestId('job-name-input');
    const jobNameInput2 = user2Page.getByTestId('job-name-input');

    // Clear existing value
    await jobNameInput1.clear();
    await expect(jobNameInput2).toHaveValue('', { timeout: 5000 });

    // Both users type simultaneously
    await Promise.all([
      jobNameInput1.type('User 1: '),
      jobNameInput2.type('User 2: '),
    ]);

    // Wait for sync
    await user1Page.waitForTimeout(2000);

    // Both should see merged result (order depends on Yjs algorithm)
    const value1 = await jobNameInput1.inputValue();
    const value2 = await jobNameInput2.inputValue();

    expect(value1).toBe(value2); // Values should match
    expect(value1).toContain('User 1: ');
    expect(value1).toContain('User 2: ');

  } finally {
    await user1Context.close();
    await user2Context.close();
  }
});
```

### Conflict Resolution

```typescript
test('conflicting changes are resolved by Yjs', async ({ browser }) => {
  const user1Context = await browser.newContext({
    storageState: 'user1-auth.json'
  });
  const user2Context = await browser.newContext({
    storageState: 'user2-auth.json'
  });

  const user1Page = await user1Context.newPage();
  const user2Page = await user2Context.newPage();

  try {
    await Promise.all([
      user1Page.goto('/collab/w/123'),
      user2Page.goto('/collab/w/123'),
    ]);

    await Promise.all([
      user1Page.waitForFunction(() => window.ydoc?.synced),
      user2Page.waitForFunction(() => window.ydoc?.synced),
    ]);

    // Disconnect User 2 from network
    await user2Context.setOffline(true);

    // Both users make conflicting changes while disconnected
    await user1Page.getByTestId('job-name-input').fill('User 1 Version');
    await user2Page.getByTestId('job-name-input').fill('User 2 Version');

    // Reconnect User 2
    await user2Context.setOffline(false);

    // Wait for Yjs to sync and resolve conflict
    await user2Page.waitForTimeout(3000);

    // Both should converge to same value (Yjs conflict resolution)
    const value1 = await user1Page.getByTestId('job-name-input').inputValue();
    const value2 = await user2Page.getByTestId('job-name-input').inputValue();

    expect(value1).toBe(value2);
    // Yjs typically uses "last writer wins" with vector clocks
    expect([value1, value2]).toContain('User 1 Version');

  } finally {
    await user1Context.close();
    await user2Context.close();
  }
});
```

## Real-Time Updates

### Server-Pushed Updates

```typescript
test('users receive real-time workflow status updates', async ({ browser }) => {
  const user1Context = await browser.newContext({
    storageState: 'user1-auth.json'
  });
  const user2Context = await browser.newContext({
    storageState: 'user2-auth.json'
  });

  const user1Page = await user1Context.newPage();
  const user2Page = await user2Context.newPage();

  try {
    await Promise.all([
      user1Page.goto('/collab/w/123'),
      user2Page.goto('/collab/w/123'),
    ]);

    await Promise.all([
      user1Page.waitForFunction(() => window.ydoc?.synced),
      user2Page.waitForFunction(() => window.ydoc?.synced),
    ]);

    // User 1 runs workflow
    await user1Page.getByRole('button', { name: 'Run' }).click();

    // Both users should see status update
    await expect(user1Page.getByTestId('workflow-status'))
      .toHaveText('Running', { timeout: 10000 });

    await expect(user2Page.getByTestId('workflow-status'))
      .toHaveText('Running', { timeout: 10000 });

    // Wait for completion
    await expect(user1Page.getByTestId('workflow-status'))
      .toHaveText('Completed', { timeout: 30000 });

    await expect(user2Page.getByTestId('workflow-status'))
      .toHaveText('Completed', { timeout: 30000 });

  } finally {
    await user1Context.close();
    await user2Context.close();
  }
});
```

### Toast Notifications

```typescript
test('users see collaborative toast notifications', async ({ browser }) => {
  const user1Context = await browser.newContext({
    storageState: 'user1-auth.json'
  });
  const user2Context = await browser.newContext({
    storageState: 'user2-auth.json'
  });

  const user1Page = await user1Context.newPage();
  const user2Page = await user2Context.newPage();

  try {
    await Promise.all([
      user1Page.goto('/collab/w/123'),
      user2Page.goto('/collab/w/123'),
    ]);

    await Promise.all([
      user1Page.waitForFunction(() => window.ydoc?.synced),
      user2Page.waitForFunction(() => window.ydoc?.synced),
    ]);

    // User 1 saves workflow
    await user1Page.getByRole('button', { name: 'Save' }).click();

    // User 1 sees success toast
    await expect(user1Page.getByText('Workflow saved'))
      .toBeVisible({ timeout: 5000 });

    // User 2 may see notification that workflow was saved by User 1
    await expect(user2Page.getByText('Editor updated workflow'))
      .toBeVisible({ timeout: 5000 });

  } finally {
    await user1Context.close();
    await user2Context.close();
  }
});
```

## Testing Network Conditions

### Offline/Online Handling

```typescript
test('handles offline and reconnection', async ({ page, context }) => {
  await page.goto('/collab/w/123');
  await page.waitForFunction(() => window.ydoc?.synced);

  // Make changes while online
  await page.getByTestId('job-name-input').fill('Online Change');

  // Go offline
  await context.setOffline(true);

  // Make changes while offline
  await page.getByTestId('job-name-input').fill('Offline Change');

  // Verify offline indicator appears
  await expect(page.getByTestId('connection-status'))
    .toHaveText('Offline', { timeout: 5000 });

  // Go back online
  await context.setOffline(false);

  // Wait for reconnection
  await expect(page.getByTestId('connection-status'))
    .toHaveText('Connected', { timeout: 10000 });

  // Changes should be synced
  const finalValue = await page.getByTestId('job-name-input').inputValue();
  expect(finalValue).toBe('Offline Change');
});
```

### Slow Network Simulation

```typescript
test('handles slow network gracefully', async ({ page, context }) => {
  // Simulate slow 3G connection
  await context.route('**/*', route => {
    setTimeout(() => route.continue(), 1000); // 1 second delay
  });

  await page.goto('/collab/w/123');

  // Connection may take longer
  await page.waitForFunction(() => window.ydoc?.synced, { timeout: 15000 });

  // Operations should still work, just slower
  await page.getByTestId('job-name-input').fill('Slow Network Test');

  // Verify loading indicators
  await expect(page.getByTestId('sync-indicator'))
    .toBeVisible({ timeout: 5000 });
});
```

## Performance Testing

### Measuring Sync Latency

```typescript
test('measure collaborative sync latency', async ({ browser }) => {
  const user1Context = await browser.newContext({
    storageState: 'user1-auth.json'
  });
  const user2Context = await browser.newContext({
    storageState: 'user2-auth.json'
  });

  const user1Page = await user1Context.newPage();
  const user2Page = await user2Context.newPage();

  try {
    await Promise.all([
      user1Page.goto('/collab/w/123'),
      user2Page.goto('/collab/w/123'),
    ]);

    await Promise.all([
      user1Page.waitForFunction(() => window.ydoc?.synced),
      user2Page.waitForFunction(() => window.ydoc?.synced),
    ]);

    // Measure time for change to propagate
    const startTime = Date.now();

    await user1Page.getByTestId('job-name-input').fill('Latency Test');

    // Wait for User 2 to see the change
    await expect(user2Page.getByTestId('job-name-input'))
      .toHaveValue('Latency Test', { timeout: 10000 });

    const latency = Date.now() - startTime;

    console.log(`Sync latency: ${latency}ms`);

    // Assert reasonable latency (adjust based on requirements)
    expect(latency).toBeLessThan(3000); // Should sync within 3 seconds

  } finally {
    await user1Context.close();
    await user2Context.close();
  }
});
```

## Common Patterns

### Multi-User Test Template

```typescript
test('collaborative feature test', async ({ browser }) => {
  // Setup
  const contexts = await Promise.all([
    browser.newContext({ storageState: 'user1-auth.json' }),
    browser.newContext({ storageState: 'user2-auth.json' }),
  ]);

  const pages = await Promise.all(contexts.map(ctx => ctx.newPage()));
  const [user1Page, user2Page] = pages;

  try {
    // Navigate all users
    await Promise.all(pages.map(page =>
      page.goto('/collab/w/123')
    ));

    // Wait for all to connect
    await Promise.all(pages.map(page =>
      page.waitForFunction(() => window.ydoc?.synced)
    ));

    // Test collaborative feature
    // ...

  } finally {
    // Cleanup
    await Promise.all(contexts.map(ctx => ctx.close()));
  }
});
```

### Wait for Sync Pattern

```typescript
async function waitForSync(page: Page, timeout = 5000): Promise<void> {
  await page.waitForFunction(() => {
    return window.ydoc?.synced === true;
  }, { timeout });
}

async function waitForValueSync(
  page: Page,
  selector: string,
  expectedValue: string,
  timeout = 5000
): Promise<void> {
  await expect(page.locator(selector))
    .toHaveValue(expectedValue, { timeout });
}
```

## Troubleshooting

### Flaky Sync Tests

**Symptom**: Tests pass sometimes, fail others

**Solution**: Increase timeouts and add explicit sync waits

```typescript
// ❌ BAD: Assumes instant sync
await user1Page.fill('input', 'value');
await expect(user2Page.locator('input')).toHaveValue('value');

// ✅ GOOD: Explicit timeout for sync
await user1Page.fill('input', 'value');
await expect(user2Page.locator('input'))
  .toHaveValue('value', { timeout: 5000 });
```

### Context Cleanup Issues

**Symptom**: Tests leak contexts or connections

**Solution**: Always close contexts in `finally` block

```typescript
test('proper cleanup', async ({ browser }) => {
  const contexts = [];
  try {
    const ctx1 = await browser.newContext();
    contexts.push(ctx1);

    // Test logic...

  } finally {
    await Promise.all(contexts.map(ctx => ctx.close()));
  }
});
```

### WebSocket Connection Issues

**Symptom**: Y.Doc never syncs

**Solution**: Verify Phoenix Channel and WebSocket connection

```typescript
test('debug connection', async ({ page }) => {
  // Log WebSocket events
  page.on('websocket', ws => {
    console.log('WebSocket:', ws.url());
    ws.on('close', () => console.log('WebSocket closed'));
  });

  // Log errors
  page.on('pageerror', error => {
    console.error('Page error:', error);
  });

  await page.goto('/collab/w/123');

  // Verify connection state
  const connected = await page.evaluate(() => {
    return {
      ydoc: !!window.ydoc,
      synced: window.ydoc?.synced,
      channel: !!(window as any).workflowChannel,
    };
  });

  console.log('Connection state:', connected);
});
```

## Best Practices

### ✅ DO

- **Use separate browser contexts** for each user
- **Close contexts in finally block** to prevent leaks
- **Add generous timeouts** for sync operations (3-5 seconds)
- **Verify Y.Doc synced state** before interactions
- **Test offline/online transitions** for robustness
- **Monitor WebSocket** for debugging sync issues
- **Test conflict resolution** with network delays
- **Measure sync latency** for performance baselines
- **Verify presence updates** for user awareness
- **Test with realistic network conditions**

### ❌ DON'T

- **Don't assume instant sync** - add explicit waits
- **Don't forget context cleanup** - use try/finally
- **Don't test without verifying connection** - check Y.Doc synced
- **Don't ignore network errors** - handle connection issues
- **Don't use fixed delays** - use condition-based waits
- **Don't test collaborative features in isolation** - need multiple users
- **Don't forget presence scenarios** - test join/leave
- **Don't skip conflict scenarios** - test concurrent edits
- **Don't hardcode timing assumptions** - use flexible timeouts
- **Don't test only happy path** - include network failures

---

**Remember**: Collaborative features depend on network timing and eventual
consistency. Always add generous timeouts, verify sync state, and test with
multiple users to ensure reliable collaborative editing experiences.
