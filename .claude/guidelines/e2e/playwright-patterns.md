# Playwright Patterns and Best Practices

## Overview

Modern Playwright (2024-2025) emphasizes auto-waiting, web-first assertions, and
semantic locators. This guide covers patterns specific to Playwright that ensure
tests are fast, stable, and maintainable.

## Core Concepts

### Auto-Waiting

Playwright automatically waits for elements to be actionable before performing
actions. This eliminates most manual waiting logic.

**✅ GOOD: Trust auto-waiting**
```typescript
test('add job to workflow', async ({ page }) => {
  // Playwright waits for button to be:
  // - Attached to DOM
  // - Visible
  // - Stable (not animating)
  // - Enabled
  // - Not obscured
  await page.getByRole('button', { name: 'Add Job' }).click();

  // Playwright waits for input to be editable
  await page.getByLabel('Job name').fill('Fetch Data');
});
```

**❌ BAD: Manual waiting**
```typescript
test('add job to workflow', async ({ page }) => {
  // Unnecessary and brittle
  await page.waitForTimeout(1000);
  await page.click('#add-job-btn');

  await page.waitForTimeout(500);
  await page.fill('#job-name', 'Fetch Data');
});
```

### Web-First Assertions

Use `expect()` with built-in matchers that auto-retry until condition is met or
timeout expires.

**✅ GOOD: Web-first assertions**
```typescript
test('workflow saves successfully', async ({ page }) => {
  await page.getByRole('button', { name: 'Save' }).click();

  // Auto-retries until text appears or times out
  await expect(page.getByText('Workflow saved')).toBeVisible();

  // Multiple conditions checked with retries
  await expect(page.getByText('Unsaved changes')).not.toBeVisible();
  await expect(page).toHaveURL(/\/w\/[a-f0-9-]+$/);
});
```

**❌ BAD: Manual waiting and assertions**
```typescript
test('workflow saves successfully', async ({ page }) => {
  await page.click('text=Save');

  // Fragile timing
  await page.waitForTimeout(2000);

  // No auto-retry
  const text = await page.textContent('#flash-message');
  expect(text).toContain('Workflow saved');
});
```

## Locator Strategies

### Priority Order

1. **Role-based** (Accessibility first)
2. **Label/Text** (User-visible)
3. **Test ID** (Stable, intentional)
4. **CSS/XPath** (Last resort)

### Role-Based Locators

Best for semantic HTML elements:

```typescript
// Buttons
await page.getByRole('button', { name: 'Save Workflow' }).click();
await page.getByRole('button', { name: /save/i }).click(); // Case insensitive

// Links
await page.getByRole('link', { name: 'Workflows' }).click();

// Inputs
await page.getByRole('textbox', { name: 'Workflow name' }).fill('ETL Pipeline');
await page.getByRole('checkbox', { name: 'Enable notifications' }).check();

// Headings
await expect(page.getByRole('heading', { name: 'Workflows' })).toBeVisible();

// Navigation
await page.getByRole('navigation', { name: 'Breadcrumb' });

// Regions (ARIA landmarks)
await page.getByRole('main'); // <main> or role="main"
await page.getByRole('banner'); // <header> or role="banner"
```

**When to use**: Semantic HTML with proper ARIA roles.

### Label-Based Locators

Best for form inputs:

```typescript
// Label association
await page.getByLabel('Job name').fill('Extract Data');
await page.getByLabel('Adaptor').selectOption('@openfn/language-http');
await page.getByLabel('Credential').selectOption('My API Key');

// Placeholder text (when no label)
await page.getByPlaceholder('Search workflows...').fill('ETL');
```

**When to use**: Form fields with associated labels.

### Text-Based Locators

Best for unique, user-visible text:

```typescript
// Exact match
await page.getByText('Workflow saved successfully').click();

// Partial match
await page.getByText('saved successfully', { exact: false });

// Regex
await page.getByText(/workflow saved/i).click();
```

**When to use**: Unique text content that's stable across translations.

### Test ID Locators

Best for elements without semantic roles or stable text:

```typescript
// Add data-testid to elements
// <div data-testid="workflow-canvas">...</div>
await page.getByTestId('workflow-canvas').click();

// Complex components
await page.getByTestId('job-node-123').hover();
await page.getByTestId('workflow-diagram').screenshot();
```

**When to use**: Dynamic content, React components, or elements without semantic
structure.

### CSS/XPath Locators (Avoid)

Last resort when other strategies don't work:

```typescript
// ❌ AVOID: Brittle CSS selectors
await page.locator('.css-xyz123 > div:nth-child(2)').click();

// ❌ AVOID: Complex XPath
await page.locator('//div[@class="container"]//span[text()="Submit"]').click();

// ✅ BETTER: Use semantic locators
await page.getByRole('button', { name: 'Submit' }).click();
```

**When to use**: Only when absolutely necessary and other options are exhausted.

## Locator Composition

### Filtering Locators

Narrow down multiple matches:

```typescript
// Get all buttons, filter by text
await page.getByRole('button').filter({ hasText: 'Delete' }).click();

// Get all list items, filter by specific text
const workflow = page.getByRole('listitem').filter({ hasText: 'ETL Pipeline' });
await workflow.click();

// Filter by child element
const card = page.locator('.card').filter({
  has: page.getByText('Completed')
});
await expect(card).toBeVisible();

// Filter by NOT having element
const emptyWorkflows = page.locator('.workflow-card').filter({
  hasNot: page.getByText('Jobs:')
});
await expect(emptyWorkflows).toHaveCount(2);
```

### Chaining Locators

Navigate from parent to child:

```typescript
// Get specific job form by index
const jobForm = page.getByTestId('job-form-0');
await jobForm.getByLabel('Job name').fill('Extract');
await jobForm.getByLabel('Adaptor').selectOption('http');
await jobForm.getByRole('button', { name: 'Save' }).click();

// Navigate through component hierarchy
const sidebar = page.getByRole('complementary');
const jobList = sidebar.getByRole('list');
await jobList.getByText('Job 1').click();
```

### Locator Operators

```typescript
// Multiple locators with AND (all must match)
await page.locator('button')
  .and(page.getByRole('button', { name: 'Save' }))
  .click();

// Multiple locators with OR (any must match)
const saveButton = page.getByRole('button', { name: 'Save' })
  .or(page.getByRole('button', { name: 'Update' }));
await saveButton.click();
```

## Advanced Waiting Strategies

### Wait for Element States

```typescript
// Wait for visibility
await page.getByText('Loading...').waitFor({ state: 'visible' });

// Wait for element to be gone
await page.getByText('Loading...').waitFor({ state: 'hidden' });

// Wait for element to be attached (exists in DOM)
await page.getByTestId('workflow-canvas').waitFor({ state: 'attached' });

// Wait for element to be detached (removed from DOM)
await page.getByTestId('modal').waitFor({ state: 'detached' });
```

### Wait for Network

```typescript
// Wait for specific request
const responsePromise = page.waitForResponse(
  response => response.url().includes('/api/workflows') &&
               response.status() === 200
);
await page.click('text=Save');
await responsePromise;

// Wait for request
const requestPromise = page.waitForRequest(
  request => request.url().includes('/api/adaptors')
);
await page.click('text=Load Adaptors');
await requestPromise;

// Wait for network idle
await page.waitForLoadState('networkidle');
```

### Wait for Function

Custom conditions:

```typescript
// Wait for global variable
await page.waitForFunction(() => window.workflowLoaded === true);

// Wait for element count
await page.waitForFunction(
  count => document.querySelectorAll('.job-node').length === count,
  5 // Expected count
);

// Wait for Redux store state
await page.waitForFunction(() => {
  return window.__REDUX_DEVTOOLS_EXTENSION__?.store
    ?.getState()
    ?.workflow
    ?.saveStatus === 'saved';
});
```

### Wait for Event

```typescript
// Wait for page event
const popupPromise = page.waitForEvent('popup');
await page.click('text=Open in new window');
const popup = await popupPromise;

// Wait for console message
const messagePromise = page.waitForEvent('console', msg =>
  msg.text().includes('Workflow saved')
);
await page.click('text=Save');
await messagePromise;

// Wait for WebSocket frame
page.on('websocket', ws => {
  ws.on('framereceived', frame => {
    console.log('Received:', frame.payload);
  });
});
```

## Network Interception and Mocking

### Intercept and Modify Responses

```typescript
test('handle slow API response', async ({ page }) => {
  // Delay API response
  await page.route('**/api/workflows', async route => {
    await new Promise(resolve => setTimeout(resolve, 3000));
    await route.continue();
  });

  await page.goto('/workflows');

  // Verify loading state
  await expect(page.getByText('Loading workflows...')).toBeVisible();
});
```

### Mock API Responses

```typescript
test('display error when API fails', async ({ page }) => {
  // Mock API failure
  await page.route('**/api/workflows', route => {
    route.fulfill({
      status: 500,
      contentType: 'application/json',
      body: JSON.stringify({ error: 'Internal server error' }),
    });
  });

  await page.goto('/workflows');

  await expect(page.getByText('Failed to load workflows')).toBeVisible();
});
```

### Mock Third-Party Services

```typescript
test('mock OAuth provider', async ({ page }) => {
  // Intercept OAuth redirect
  await page.route('**/auth/google', route => {
    route.fulfill({
      status: 302,
      headers: {
        'Location': '/auth/callback?code=mock-code&state=mock-state'
      },
    });
  });

  // Intercept token exchange
  await page.route('**/oauth/google/token', route => {
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        access_token: 'mock-token',
        token_type: 'Bearer'
      }),
    });
  });

  await page.click('text=Sign in with Google');

  // Should be logged in without hitting real Google OAuth
  await expect(page.getByText('Welcome')).toBeVisible();
});
```

### Block Resources

Speed up tests by blocking unnecessary resources:

```typescript
test.beforeEach(async ({ page }) => {
  // Block images, fonts, and media
  await page.route('**/*.{png,jpg,jpeg,svg,woff,woff2,ttf}', route =>
    route.abort()
  );

  // Block analytics and tracking
  await page.route('**/analytics/**', route => route.abort());
  await page.route('**/tracking/**', route => route.abort());
});
```

## Performance Measurement

### Core Web Vitals

```typescript
test('workflow editor loads with good performance', async ({ page }) => {
  await page.goto('/workflows/123/edit');

  const metrics = await page.evaluate(() => {
    return new Promise<any>((resolve) => {
      const vitals = { lcp: 0, fid: 0, cls: 0, fcp: 0, ttfb: 0 };

      // Largest Contentful Paint
      new PerformanceObserver((list) => {
        const entries = list.getEntries();
        const lastEntry = entries[entries.length - 1] as any;
        vitals.lcp = lastEntry.renderTime || lastEntry.loadTime;
      }).observe({ type: 'largest-contentful-paint', buffered: true });

      // First Contentful Paint
      const paintEntries = performance.getEntriesByType('paint');
      const fcpEntry = paintEntries.find(e => e.name === 'first-contentful-paint');
      if (fcpEntry) vitals.fcp = fcpEntry.startTime;

      // Time to First Byte
      const navEntry = performance.getEntriesByType('navigation')[0] as any;
      if (navEntry) vitals.ttfb = navEntry.responseStart;

      // Cumulative Layout Shift
      new PerformanceObserver((list) => {
        for (const entry of list.getEntries()) {
          if (!(entry as any).hadRecentInput) {
            vitals.cls += (entry as any).value;
          }
        }
      }).observe({ type: 'layout-shift', buffered: true });

      setTimeout(() => resolve(vitals), 3000);
    });
  });

  // Assert performance budgets
  expect(metrics.lcp).toBeLessThan(2500); // Good: < 2.5s
  expect(metrics.fcp).toBeLessThan(1800); // Good: < 1.8s
  expect(metrics.cls).toBeLessThan(0.1);  // Good: < 0.1
  expect(metrics.ttfb).toBeLessThan(800); // Good: < 800ms

  console.log('Performance Metrics:', metrics);
});
```

### Custom Performance Marks

```typescript
test('measure workflow save duration', async ({ page }) => {
  await page.goto('/workflows/123/edit');

  // Add performance mark
  await page.evaluate(() => performance.mark('save-start'));

  await page.getByRole('button', { name: 'Save' }).click();
  await expect(page.getByText('Workflow saved')).toBeVisible();

  // Measure duration
  const duration = await page.evaluate(() => {
    performance.mark('save-end');
    performance.measure('save-workflow', 'save-start', 'save-end');
    const measure = performance.getEntriesByName('save-workflow')[0];
    return measure.duration;
  });

  console.log(`Workflow save took ${duration}ms`);
  expect(duration).toBeLessThan(2000); // Should save within 2 seconds
});
```

## Assertions

### Element Visibility

```typescript
// Visible
await expect(page.getByText('Workflow saved')).toBeVisible();

// Hidden
await expect(page.getByText('Loading...')).toBeHidden();

// Attached to DOM (may not be visible)
await expect(page.getByTestId('hidden-input')).toBeAttached();

// Detached from DOM
await expect(page.getByTestId('modal')).not.toBeAttached();
```

### Element State

```typescript
// Enabled/Disabled
await expect(page.getByRole('button', { name: 'Save' })).toBeEnabled();
await expect(page.getByRole('button', { name: 'Delete' })).toBeDisabled();

// Checked/Unchecked
await expect(page.getByRole('checkbox', { name: 'Agree' })).toBeChecked();
await expect(page.getByRole('checkbox', { name: 'Subscribe' })).not.toBeChecked();

// Editable
await expect(page.getByLabel('Workflow name')).toBeEditable();

// Focused
await expect(page.getByLabel('Job name')).toBeFocused();
```

### Element Content

```typescript
// Text content
await expect(page.getByRole('heading')).toHaveText('Workflows');
await expect(page.getByRole('heading')).toHaveText(/workflows/i);

// Partial text
await expect(page.getByTestId('job-count')).toContainText('5 jobs');

// Value (form inputs)
await expect(page.getByLabel('Workflow name')).toHaveValue('ETL Pipeline');

// Attribute
await expect(page.getByTestId('workflow')).toHaveAttribute('data-status', 'active');

// CSS class
await expect(page.getByTestId('workflow')).toHaveClass(/active/);
await expect(page.getByTestId('workflow')).toHaveClass('workflow-item active');
```

### Element Count

```typescript
// Exact count
await expect(page.getByRole('listitem')).toHaveCount(5);

// At least/most
await expect(page.locator('.job-node')).toHaveCount.greaterThan(0);
await expect(page.locator('.error')).toHaveCount.lessThan(1);
```

### Page Assertions

```typescript
// URL
await expect(page).toHaveURL('/workflows/123');
await expect(page).toHaveURL(/\/workflows\/[a-f0-9-]+/);

// Title
await expect(page).toHaveTitle('Lightning - Workflows');
await expect(page).toHaveTitle(/Workflows/);

// Screenshot comparison
await expect(page).toHaveScreenshot('workflow-canvas.png');
```

## File Operations

### File Upload

```typescript
test('upload workflow configuration', async ({ page }) => {
  await page.goto('/workflows/import');

  // Single file
  await page.getByLabel('Upload workflow').setInputFiles('workflow.json');

  // Multiple files
  await page.getByLabel('Upload files').setInputFiles([
    'workflow1.json',
    'workflow2.json'
  ]);

  // From buffer
  await page.getByLabel('Upload').setInputFiles({
    name: 'workflow.json',
    mimeType: 'application/json',
    buffer: Buffer.from(JSON.stringify({ name: 'Test' }))
  });

  // Clear file input
  await page.getByLabel('Upload').setInputFiles([]);
});
```

### File Download

```typescript
test('download workflow export', async ({ page }) => {
  await page.goto('/workflows/123');

  const downloadPromise = page.waitForEvent('download');
  await page.getByRole('button', { name: 'Export' }).click();
  const download = await downloadPromise;

  // Verify filename
  expect(download.suggestedFilename()).toBe('workflow-123.json');

  // Save to disk
  await download.saveAs(`/tmp/${download.suggestedFilename()}`);

  // Read content
  const content = await download.path();
  const data = require('fs').readFileSync(content, 'utf-8');
  const workflow = JSON.parse(data);

  expect(workflow.name).toBe('ETL Pipeline');
});
```

## Debugging Utilities

### Console Logs

```typescript
test('debug test', async ({ page }) => {
  // Listen to console
  page.on('console', msg => {
    console.log(`[${msg.type()}]`, msg.text());
  });

  // Listen to page errors
  page.on('pageerror', error => {
    console.error('Page error:', error.message);
  });

  await page.goto('/workflows');
});
```

### Request Logging

```typescript
test('debug network', async ({ page }) => {
  // Log all requests
  page.on('request', request => {
    console.log('>>', request.method(), request.url());
  });

  // Log responses
  page.on('response', response => {
    console.log('<<', response.status(), response.url());
  });

  await page.goto('/workflows');
});
```

### Screenshots and Videos

```typescript
test('capture evidence', async ({ page }) => {
  await page.goto('/workflows/123');

  // Full page screenshot
  await page.screenshot({ path: 'workflow.png', fullPage: true });

  // Element screenshot
  await page.getByTestId('workflow-canvas')
    .screenshot({ path: 'canvas.png' });

  // Video recording (configure in playwright.config.ts)
  // video: 'on' or 'retain-on-failure'
});
```

## Common Patterns

### Polling for Conditions

```typescript
test('wait for workflow execution', async ({ page }) => {
  await page.goto('/workflows/123');
  await page.getByRole('button', { name: 'Run' }).click();

  // Poll until status is "completed"
  await expect(async () => {
    const status = await page.getByTestId('workflow-status').textContent();
    expect(status).toBe('Completed');
  }).toPass({
    intervals: [1000, 2000, 5000], // Exponential backoff
    timeout: 30000,
  });
});
```

### Handling Alerts

```typescript
test('confirm workflow deletion', async ({ page }) => {
  // Listen for dialog before triggering
  page.on('dialog', dialog => {
    expect(dialog.message()).toBe('Delete this workflow?');
    dialog.accept();
  });

  await page.goto('/workflows/123');
  await page.getByRole('button', { name: 'Delete' }).click();

  // Workflow should be deleted
  await expect(page).toHaveURL('/workflows');
});
```

### Multiple Browser Contexts

```typescript
test('isolated user sessions', async ({ browser }) => {
  // Admin context
  const adminContext = await browser.newContext({
    storageState: 'admin-auth.json'
  });
  const adminPage = await adminContext.newPage();
  await adminPage.goto('/admin');

  // Editor context
  const editorContext = await browser.newContext({
    storageState: 'editor-auth.json'
  });
  const editorPage = await editorContext.newPage();
  await editorPage.goto('/workflows');

  // Both sessions are completely isolated
  await expect(adminPage.getByText('Admin Dashboard')).toBeVisible();
  await expect(editorPage.getByText('Workflows')).toBeVisible();

  await adminContext.close();
  await editorContext.close();
});
```

## Anti-Patterns to Avoid

### ❌ Fixed Timeouts

```typescript
// BAD: Arbitrary wait
await page.waitForTimeout(3000);
await page.click('text=Save');

// GOOD: Wait for specific condition
await page.getByRole('button', { name: 'Save' }).click();
await expect(page.getByText('Saved')).toBeVisible();
```

### ❌ Polling with Loops

```typescript
// BAD: Manual polling
let saved = false;
for (let i = 0; i < 10; i++) {
  const text = await page.textContent('#status');
  if (text === 'Saved') {
    saved = true;
    break;
  }
  await page.waitForTimeout(1000);
}
expect(saved).toBe(true);

// GOOD: Use auto-retry assertions
await expect(page.locator('#status')).toHaveText('Saved');
```

### ❌ Multiple await in Assertions

```typescript
// BAD: Loses auto-retry behavior
const text = await page.textContent('#status');
expect(text).toBe('Saved');

// GOOD: Assertion includes auto-retry
await expect(page.locator('#status')).toHaveText('Saved');
```

### ❌ Fragile Selectors

```typescript
// BAD: Implementation-specific
await page.locator('.css-xyz123 > div:nth-child(2)').click();

// GOOD: Semantic selector
await page.getByRole('button', { name: 'Save' }).click();
```

---

**Remember**: Playwright's auto-waiting and web-first assertions handle most
timing issues automatically. Trust the framework, use semantic locators, and
write assertions that naturally retry until conditions are met.
